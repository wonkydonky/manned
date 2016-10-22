#[macro_use] extern crate log;
extern crate env_logger;
extern crate libarchive;
extern crate regex;

use regex::Regex;

mod archive;


// Checks a path for a man page candidate. Returns None if it doesn't seem like a man page
// location, otherwise Some((manPageName, Section, Locale)).
fn parse_path(path: &str) -> Option<(&str, &str, &str)> {
    // Roughly: man[/locale]/man1/manpage.section[.compression]+
    // TODO: lazy_static
    let re = Regex::new(r"(?x)
        man
        (?: / ([^/]+) )?   # Optional locale
        /man[a-z0-9]/      # Subdir
        ([^/]+?)           # Man page name (non-greedy)
        \. ([^/\.]+)       # Section
        (?: \. (?: gz|lzma|bz2|xz ))* $  # Any number of compression extensions
    ").unwrap();

    let cap = match re.captures(path) { Some(x) => x, None => return None };
    let locale = cap.at(1).unwrap_or("");
    let name = cap.at(2).unwrap();
    let section = cap.at(3).unwrap();

    // Not everything matching the regex is necessarily a man page, exclude some special cases.
    match (name, section, locale) {
        // Files that totally aren't man pages
        ("Makefile",   "in",   _) |
        ("Makefile",   "am",   _) |
        (".cvsignore",  _,     _) |
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


fn main() {
    env_logger::init().unwrap();
    info!("Hello, world!");
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
