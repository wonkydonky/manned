use std::str;
use std::io;
use std::io::Read;
use regex::bytes;
use regex::Regex;
use encoding;
use encoding::{all,EncodingRef};
use encoding::label::encoding_from_whatwg_label;
use ring::digest;

use archive::Archive;

// Anything larger than this just isn't a man page. I hope.
const MAX_MAN_SIZE: u64 = 20*1024*1024;
// I've also not seen valid man pages smaller than this
const MIN_MAN_SIZE: u64 = 9;


// Checks a path for a man page candidate. Returns None if it doesn't seem like a man page
// location, otherwise Some((manPageName, Section, Locale)).
pub fn parse_path(path: &str) -> Option<(&str, &str, &str)> {
    // Roughly: man[/locale]/man1/manpage.section[.compression]+
    lazy_static! {
        static ref RE: Regex = Regex::new(r"(?x)
            man
            (?: / ([^/]+) )?   # Optional locale
            /man[a-z0-9]/      # Subdir
            ([^/]+?)           # Man page name (non-greedy)
            \. ([^/\.]+)       # Section
            (?: \. (?: gz|lzma|bz2|xz ))* $  # Any number of compression extensions
        ").unwrap();
    }

    let cap = match RE.captures(path) { Some(x) => x, None => return None };
    let locale = cap.at(1).unwrap_or("");
    let name = cap.at(2).unwrap();
    let section = cap.at(3).unwrap();

    // Not everything matching the regex is necessarily a man page, exclude some special cases.
    match (name, section, locale) {
        // Files that totally aren't man pages
        ("Makefile",   "am",   _) |
        (".cvsignore",  _,     _) |
        (_,            "in",   _) |
        (_,            "gz",   _) |
        (_,            "lzma", _) |
        (_,            "bz2",  _) |
        (_,            "xz",   _) |
        (_,            "html", _) => None,
        // Some weird directories that happen to match the locale
        (n, s, "5man") |
        (n, s, "c")    |
        (n, s, "man1") |
        (n, s, "man2") |
        (n, s, "man3") |
        (n, s, "man4") |
        (n, s, "man5") |
        (n, s, "man6") |
        (n, s, "man7") |
        (n, s, "man8") |
        (n, s, "Man-Part1") |
        (n, s, "Man-Part2") => Some((n, s, "")),
        // Nothing special!
        x => Some(x)
    }
}


// Convenient wrapper for archread's interest_cb
pub fn ismanpath(path: &str) -> bool {
    parse_path(path).is_some()
}


fn validate(data: &Vec<u8>) -> Option<&'static str> {
    lazy_static! {
        static ref HTML: bytes::Regex = bytes::Regex::new(r"^\s*<(?:html|head|!DOCTYPE)").unwrap();
    }

    if data.len() >= MAX_MAN_SIZE as usize {
        Some("File too large")
    } else if data.len() < MIN_MAN_SIZE as usize {
        Some("File too small")
    } else if &data[..] == &b".so man3/\n"[..] {
        Some("Contents: '.so man3/'")
    } else if &data[..] == &b"timestamp\n"[..] {
        Some("Contents: 'timestamp'")
    } else if &data[..] == &b"\x75ELF"[..] {
        Some("Looks like an ELF binary")
    } else if HTML.is_match(&data) {
        Some("Looks like an HTML file")
    } else {
        None
    }
}


// Look for 'coding:' indications in the file header, a la preconv(1).
fn codec_from_tag(data: &Vec<u8>) -> Option<EncodingRef> {
    lazy_static! {
        // According to the emacs docs the tag should be on the first line; according to preconv(1)
        // it should be on the first or second line. I've also seen some files with the tag on the
        // last line. I've not seen the tag itself used in a different context, so just get it from
        // anywhere...
        static ref TAG: bytes::Regex = bytes::Regex::new(r"-\*-.*coding:\s*(?u:([^\s;]+)).*-\*").unwrap();
    }
    let cap = match TAG.captures(&data) { Some(x) => x, None => return None };
    let tag = str::from_utf8(cap.at(1).unwrap()).unwrap().to_lowercase();

    match &tag[..] {
        // Deny some common UTF-8-compatible encodings. These tags are obviously incorrect.
        "us-ascii" | "ascii" | "utf8" | "utf-8" | "utf-8-unix" => None,

        // latin-1 isn't in the whatwg spec under that name
        "latin-1" => Some(all::WINDOWS_1252),

        // armscii isn't in the whatwg spec at all
        "armscii-8" => Some(all::ARMSCII_8),

        // Anything else should be found by its whatwg label.
        x => match encoding_from_whatwg_label(x) {
            Some(x) => Some(x),
            None => { warn!("Unknown encoding in emacs tag: {}", x); None },
        }
    }
}


fn codec_from_path(path: &str) -> Option<EncodingRef> {
    let locale = match parse_path(path) {
        Some((_,_,l)) if l != "" => l.to_lowercase(),
        _ => return None,
    };

    lazy_static! {
        static ref RE: Regex = Regex::new(r"^(?x)
           ([a-z]+)           # primary language
           (?:_  ([a-z]+))?   # secondary language
           (?:@  [a-z]+)?     # script (potentially useful, but uncommon and not currently used)
           (?:\. ([^\.@]+))?  # encoding (FUCKING USEFUL)
        $").unwrap();
    }

    let cap = match RE.captures(&locale) { Some(x) => x, None => return None };
    let lang = cap.at(1).unwrap();
    let seclang = cap.at(2);
    let enc = cap.at(3);

    // Try to do something with the encoding tag
    match (lang, enc) {
        (_,    Some("eucjp")) |
        (_,    Some("ujis")) | // Not sure about this one, but it seems to come out alright
        ("ja", Some("euc")) => return Some(all::EUC_JP),

        (_,    Some("euckr")) => return Some(all::WINDOWS_949),

        /* Not sure if PCK is just an alias for SJIS or if there's more of a difference, but it
         * certainly looks like a SJIS-like encoding. */
        ("ja", Some("pck")) => return Some(all::WINDOWS_31J),

        /* This is apparently some variant of ISO-2022-JP */
        ("ja", Some("jis7")) => return Some(all::ISO_2022_JP),

        (_,    Some(x)) => match encoding_from_whatwg_label(x) {
            Some(x) => return Some(x),
            _ => { warn!("Unknown encoding in locale: {}", x) },
        },
        _ => {},
    };

    // Fall back to language
    match (lang, seclang) {
        ("pl", _) |
        ("cs", _) |
        ("hr", _) |
        ("hu", _) |
        ("sl", _) |
        ("sk", _) => Some(all::ISO_8859_2),
        ("bg", _) |
        ("be", _) |
        ("uk", _) => Some(all::ISO_8859_5),
        ("el", _) => Some(all::ISO_8859_7),
        ("et", _) => Some(all::ISO_8859_15),
        ("tr", _) => Some(all::WINDOWS_1254),
        ("ru", _) => Some(all::KOI8_R),
        ("ja", _) |
        ("jp", _) => Some(all::EUC_JP), // Tricky; but JIS is certainly less common
        ("zh", Some("cn")) => Some(all::GBK),  // These are based purely on what I've observed,
        ("zh", _) => Some(all::BIG5_2003),     // perhaps some heuristics based on contents can do better
        ("ko", _) => Some(all::WINDOWS_949),
        (_, _) => None,
    }
}


// Decompresses / decodes a man page and returns its SHA-1 hash, encoding name, and UTF-8 contents.
pub fn decode(paths: &[&str], ent: &mut Read) -> io::Result<(digest::Digest,&'static str,String)> {
    let mut decomp = try!(Archive::open_raw(ent)).take(MAX_MAN_SIZE+1);
    let mut data = Vec::new();
    try!(decomp.read_to_end(&mut data));

    if let Some(e) = validate(&data) {
        return Err(io::Error::new(io::ErrorKind::InvalidData, e));
    }

    let dig = digest::digest(&digest::SHA1, &data);

    // TODO: Handle BOM? UTF-16?
    // TODO: This fails badly for ISO-2022-JP. How the hell do we cleanly fix that?
    // If it passes as UTF-8, then just consider it UTF-8.
    if let Ok(_) = str::from_utf8(&data) {
        return Ok((dig, "utf8", unsafe { String::from_utf8_unchecked(data) } ));
    }
    // Otherwise, look for a coding tag in the contents
    if let Some(e) = codec_from_tag(&data) {
        if let Ok(s) = e.decode(&data, encoding::DecoderTrap::Strict) {
            return Ok((dig, e.name(), s));
        }
    }
    // If that fails as well, look for clues in the file path.
    for path in paths {
        if let Some(e) = codec_from_path(path) {
            if let Ok(s) = e.decode(&data, encoding::DecoderTrap::Strict) {
                return Ok((dig, e.name(), s));
            }
        }
    }
    // If all else fails, use a lossy iso-8859-1
    Ok((dig, "iso-8859-1", (all::ISO_8859_1 as EncodingRef).decode(&data, encoding::DecoderTrap::Ignore).unwrap() ))
}




#[test]
fn test_parse_path() {
    // Generic tests
    assert_eq!(parse_path("/"), None);
    assert_eq!(parse_path("/man1/ncdu.1"), None);
    assert_eq!(parse_path("/man/man?/ncdu.1"), None);
    assert_eq!(parse_path("/man/man1/ncdu.1"), Some(("ncdu", "1", "")));
    assert_eq!(parse_path("/man/man1/ncdu.1.gz.lzma.xz.bz2.gz"), Some(("ncdu", "1", ""))); // This stuff happens
    assert_eq!(parse_path("/man/en_US.UTF-8/man1/ncdu.1"), Some(("ncdu", "1", "en_US.UTF-8")));

    // Special cases
    assert_eq!(parse_path("/usr/share/man/man1/INDEX"), None);
    assert_eq!(parse_path("/usr/share/man/man1/Makefile"), None);
    assert_eq!(parse_path("/usr/share/man/man1/Makefile.am"), None);
    assert_eq!(parse_path("/usr/share/man/man1/Makefile.in"), None);
    assert_eq!(parse_path("/usr/share/man/man1/.cvsignore"), None);
    assert_eq!(parse_path("/usr/share/man/man1/.cvsignore.gz"), None);

    // Some actual locations
    assert_eq!(parse_path("/usr/local/man/man1/list_audio_tracks.1.gz"), Some(("list_audio_tracks", "1", "")));
    assert_eq!(parse_path("/usr/local/lib/perl5/site_perl/man/man3/DBIx::Class::Helper::ResultSet::DateMethods1::Announcement.3.gz"), Some(("DBIx::Class::Helper::ResultSet::DateMethods1::Announcement", "3", "")));
    assert_eq!(parse_path("/usr/man/man3/exit.3tk"), Some(("exit", "3tk", "")));
    assert_eq!(parse_path("/usr/local/brlcad/share/man/mann/exit.nged.gz"), Some(("exit", "nged", "")));
    assert_eq!(parse_path("/usr/X11R6/man/man3/intro.3xglut.gz"), Some(("intro", "3xglut", "")));
    assert_eq!(parse_path("/usr/local/share/man/ko_KR.eucKR/man3/intro.3.gz"), Some(("intro", "3", "ko_KR.eucKR")));

    assert_eq!(parse_path("/usr/lib/scilab/man/Man-Part1/man1/ans.1"), Some(("ans", "1", "")));
    assert_eq!(parse_path("/heirloom/usr/share/man/5man/man1/chgrp.1.gz"), Some(("chgrp", "1", "")));

    assert_eq!(parse_path("/usr/local/plan9/man/man8/index.html"), None);
    assert_eq!(parse_path("/usr/local/share/doc/gmt/html/man/grdpaste.html"), None);
}


#[test]
fn test_codec_from_path() {
    let t = |p,n| {
        assert_eq!(codec_from_path(p).unwrap().name(), n);
    };
    t("man/de_DE.ISO8859-15/man1/scribus.1.gz", "iso-8859-15");
    t("man/de_DE.ISO_8859-1/man1/scribus.1.gz", "windows-1252");
    t("man/ja.UTF-8/man1/test.1", "utf-8");
    t("man/ja_JP/man1/test.1", "euc-jp");
    t("man/ja_JP.EUC/man1/test.1", "euc-jp");
    t("man/ja_JP.SJIS/man1/test.1", "windows-31j");
    t("man/jp.eucJP/man1/test.1", "euc-jp");
    t("man/jp/man1/test.1", "euc-jp");
    t("man/lt.ISO8859-13/man1/test.1", "iso-8859-13");
    t("man/ru/man1/test.1", "koi8-r");
    t("man/ru_RU@Cyr/man1/test.1", "koi8-r");
    t("man/zh_CN/man1/test.1", "gbk");
    t("man/zh_TW/man1/test.1", "big5-2003");
}


#[test]
fn test_decode_zh() {
    use std::fs::File;
    use ring::test::from_hex;

    // cat exit.1.gz | lzma -d | gzip -d | sha1sum
    let filehash = from_hex("cdf9b3e8d96a83c908eb0a0c277485e2f3eebe87").unwrap();
    // cat exit.1.gz | lzma -d | gzip -d | iconv -f gbk -t utf8 | sha1sum
    let utf8hash = from_hex("47f3e441137b207c0abdc38adac692298da4927a").unwrap();

    let mut f = File::open("tests/exit.3.gz.lzma").unwrap();
    let (dig, enc, s) = decode(&["bullshit", "/usr/share/man/zh_CN/man3/exit.3.gz"][..], &mut f).unwrap();

    assert_eq!(dig.as_ref(), &filehash[..]);
    assert_eq!(enc, "gbk");

    let utf8dig = digest::digest(&digest::SHA1, s.as_bytes());
    assert_eq!(utf8dig.as_ref(), &utf8hash[..]);
}
