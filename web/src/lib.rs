#![feature(test)]
extern crate test;
extern crate regex;
#[macro_use] extern crate lazy_static;

use std::fmt::Write;
use regex::Regex;


#[derive(Clone,Copy,PartialEq,Eq)]
enum FmtChar {
    Regular,
    Italic,
    Bold,
}


/* Simple state machine to parse the following grammar:
 *
 * fmtchar       = escape | double-escape | char
 * escape        = tag ESC char
 * double-escape = ESC tag ESC char
 * tag           = "_"  # italic
 *               | char # bold
 *
 * This format is described as "old behaviour" in grotty(1).  The double-escape
 * seems to be a weird glitch, and can be interpreted as
 * "(tag ESC char) ESC (tag ESC char)".  This parser simply skips over any such
 * sequence starting with ESC. */
enum CharParse {
    Start,
    One(char),      // Seen a single character (either 'char' or 'escape')
    Escape(char),   // Seen a single character + escape
    DoubleEsc(u32), // Inside a double-escape, indicates number of characters left to skip
}


impl CharParse {
    fn update(&mut self, chr: char) -> Option<(char, FmtChar)> {
        match *self {

            CharParse::Start => {
                *self = if chr == 8 as char { CharParse::DoubleEsc(2) } else { CharParse::One(chr) };
                None
            },

            CharParse::One(c) =>
                if chr == 8 as char {
                    *self = CharParse::Escape(c);
                    None
                } else {
                    *self = CharParse::One(chr);
                    Some((c, FmtChar::Regular))
                },

            CharParse::Escape(c) => {
                *self = CharParse::Start;
                Some((chr, if c == '_' { FmtChar::Italic } else { FmtChar::Bold }))
            },

            CharParse::DoubleEsc(n) => {
                *self = if n == 0 { CharParse::Start } else { CharParse::DoubleEsc(n-1) };
                None
            },
        }
    }
}


fn pushfmt(out: &mut String, old: FmtChar, new: FmtChar) {
    if new != old && old != FmtChar::Regular {
        out.push_str(if old == FmtChar::Italic { "</i>" } else { "</b>" });
    }
    if new != old && new != FmtChar::Regular {
        out.push_str(if new == FmtChar::Italic { "<i>" } else { "<b>" });
    }
}


// Intermediate text buffer. This buffer contains the entire HTML-escaped man page and a list of
// indices where text formatting changes are performed.
struct FmtBuf {
    buf: String,
    // List of formatting chunks. The number indicates the character index where the formatting
    // ends. E.g. [(5,Regular),(10,Bold),(15,Italic)] means:
    //   [0..5] is Regular
    //   [5..10] is Bold
    //   [10..15] is Italic
    fmt: Vec<(usize,FmtChar)>,
    lastfmt: FmtChar,
}

// Output state
struct Flush<'a, 'b> {
    out: &'a mut String,
    idx: usize, // Last byte in the buffer that has been processed
    fmt: std::iter::Peekable<std::slice::Iter<'b, (usize,FmtChar)>>, // Iterator over FmtBuf.fmt
}


impl FmtBuf {
    fn push(&mut self, chr: char, fmt: FmtChar) {
        // Consider whitespace and underscore to have the same
        // formatting as the previous character; This generates smaller
        // HTML, and you can't see the difference anyway.
        if self.lastfmt != fmt && !(chr == ' ' || chr == '_') {
            self.fmt.push((self.buf.len(), self.lastfmt));
            self.lastfmt = fmt;
        }
        match chr {
            '>' => self.buf.push_str("&gt;"),
            '<' => self.buf.push_str("&lt;"),
            '&' => self.buf.push_str("&amp;"),
            // '"' => self.buf.push_str("&quot;"), // TEMPORARILY disabled for comparison with old code
            _   => self.buf.push(chr), // <- 30% of the entire processing time is spent here.
        }
    }

    // Flush all unprocessed bytes until 'end' to the output
    fn flush_to(&self, st: &mut Flush, end: usize) {
        let mut lastfmt = FmtChar::Regular;
        while st.idx < end {
            let &&(chunk, fmt) = st.fmt.peek().unwrap();
            let chunk = if chunk > end {
                end
            } else {
                st.fmt.next();
                chunk
            };
            pushfmt(st.out, lastfmt, fmt);
            st.out.push_str(&self.buf[st.idx..chunk]);
            st.idx = chunk;
            lastfmt = fmt;
        }
        pushfmt(st.out, lastfmt, FmtChar::Regular);
    }

    // Consume the input buffer until 'end' without generating output
    fn flush_skip(&self, st: &mut Flush, end: usize) {
        st.idx = end;
        while st.fmt.peek().unwrap().0 <= st.idx {
            st.fmt.next();
        }
    }

    fn flush_include(&self, st: &mut Flush, start: usize, end: usize) {
        lazy_static!(
            static ref REF: Regex = Regex::new(r"^((?:[^\s\]]*/)?([^\s/\]]+))\]\]\]").unwrap();
        );
        let m = match REF.captures(&self.buf[end..]) { Some(x) => x, None => return };

        self.flush_to(st, start);
        st.out.push_str("\n&gt;&gt; Included man page: <a href=\"/");
        // Replace ‐ (U+2010) with - (U+2d). ASCII dashes are replaced with an Unicode dash
        // when passed through groff, which we need to revert in order to get the link working.
        // (Apparently it recognizes man page references and URLs, as it doesn't do this
        // replacement in those situations.)
        for c in m[2].chars() {
            st.out.push(if c == '‐' { '-' } else { c });
        }
        st.out.push_str("\">");
        st.out.push_str(&m[1]);
        st.out.push_str("</a>");
        self.flush_skip(st, end + m[0].len());
    }

    fn flush_url(&self, st: &mut Flush, start: usize) {
        lazy_static!(
            // Some characters considered to never be part of a URL.
            // (Note that we can't match literal ><" because of the HTML escaping done previously)
            static ref URLEND: Regex = Regex::new("(?:\"|&quot;|&gt;|&lt;|\\s)").unwrap();
        );
        let urlend = match URLEND.find(&self.buf[start..]) { Some(x) => x, None => return };

        self.flush_to(st, start);
        let url = &self.buf[start..(start + urlend.start())];

        // Also catch a Unicode '⟩', which is how groff sometimes ends a .UR, e.g.:
        // - https://manned.org/troff/c4467840
        // - https://manned.org/pass/78413b49
        // - https://manned.org/empathy-accounts/8c05b2c1
        // - https://manned.org/urn/8cb83e85
        // TODO: Check the character before the start of the URL, and only remove ) if there is a
        // starting ( before it.
        let url = url.trim_right_matches('.').trim_right_matches(',').trim_right_matches(';').trim_right_matches(')').trim_right_matches('⟩');

        write!(st.out, "<a href=\"{0}\" rel=\"nofollow\">{0}</a>", url).unwrap();
        self.flush_skip(st, start + url.len());
    }

    fn flush_ref(&self, st: &mut Flush, end: usize) {
        // We know where the closing bracket is in the string, so this regex is used to search
        // backwards from there and find the start of the reference.
        lazy_static!(
            static ref REF: Regex = Regex::new(r"([A-Za-z0-9\._-]+)\(([1-8nl])\)$").unwrap();
        );

        // Disallow some characters following a reference
        if self.buf.len() > end {
            let ch = self.buf[end..].chars().next().unwrap();
            if ch == '-' || ch == '_' || ch.is_alphanumeric() {
                return;
            }
        }

        let m = REF.captures(&self.buf[..end]).unwrap();
        self.flush_to(st, end - m[0].len());
        self.flush_skip(st, end);
        write!(st.out, "<a href=\"/{}.{}\">{}</a>", &m[1], &m[2], &m[0]).unwrap();
    }

    fn flush(&mut self, out: &mut String) {
        self.fmt.push((self.buf.len(), FmtChar::Regular));

        // Find the indices where the first line ends, and the last line starts. These are used to
        // efficiently disable reference formatting on the first and last line.
        let firstlineend = self.buf.find('\n').unwrap_or(self.buf.len());
        let lastlinestart = self.buf.trim_right_matches('\n').rfind('\n').unwrap_or(0);

        // This regex is used to quickly *find* interesting patterns, any further validation
        // and processing is done afterwards by the (slower) specialized flush_ methods.
        lazy_static!(
            static ref SEARCH: Regex = Regex::new(r"(?m)(^\[\[\[MANNEDINCLUDE|https?://|[A-Za-z0-9]+\([1-8nl]\))").unwrap();
        );

        let mut st = Flush{
            out: out,
            idx: 0,
            fmt: self.fmt.iter().peekable(),
        };

        for i in SEARCH.find_iter(&self.buf) {
            // This can happen with overlapping detections, e.g. when something inside a URL looks
            // like a man page reference.
            if st.idx > i.start() {
                continue;
            }
            let allowref = i.start() > firstlineend && i.start() < lastlinestart;
            match self.buf.as_bytes()[i.end()-1] {
                0x45 /* E */ => self.flush_include(&mut st, i.start(), i.end()),
                0x2F /* / */ if allowref => self.flush_url(&mut st, i.start()),
                _            if allowref => self.flush_ref(&mut st, i.end()),
                _ => {}
            }
        }
        self.flush_to(&mut st, self.buf.len());
    }
}


pub fn grotty2html(input: &str) -> String {
    let mut state = CharParse::Start;

    let mut buf = FmtBuf{
        buf: String::with_capacity(128),
        fmt: Vec::with_capacity(128),
        lastfmt: FmtChar::Regular,
    };

    for chr in input.chars() {
        if let Some((chr, fmt)) = state.update(chr) {
            buf.push(chr, fmt);
            // Line-based flushing is also possible, but not as fast.
            //if chr == '\n' {
            //    buf.flush(&mut out);
            //    buf.buf.clear();
            //    buf.fmt.clear();
            //    buf.lastfmt = FmtChar::Regular;
            //}
        }
    }
    if let CharParse::One(chr) = state {
        buf.push(chr, FmtChar::Regular);
    }

    let mut out = String::with_capacity(input.len());
    buf.flush(&mut out);
    out
}



use std::os::raw::c_ulonglong;

#[repr(C)]
pub struct StringWrap {
    buf: *mut u8,
    len: c_ulonglong,
    cap: c_ulonglong,
}

#[no_mangle]
pub extern fn grotty2html_wrap(in_buf: *const u8, in_len: c_ulonglong) -> StringWrap {
    let input = unsafe { std::str::from_utf8_unchecked( std::slice::from_raw_parts(in_buf, in_len as usize) ) };
    let mut out = grotty2html(input).into_bytes();
    let r = StringWrap {
        buf: out.as_mut_ptr(),
        len: out.len() as c_ulonglong,
        cap: out.capacity() as c_ulonglong,
    };
    std::mem::forget(out);
    r
}

#[no_mangle]
pub extern fn grotty2html_free(buf: StringWrap) {
    unsafe { Vec::from_raw_parts(buf.buf, buf.len as usize, buf.cap as usize) };
}


#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use test::Bencher;

    fn bench_file(b: &mut Bencher, f: &str) {
        let mut f = std::fs::File::open(f).unwrap();
        let mut buf = String::new();
        f.read_to_string(&mut buf).unwrap();

        b.iter(|| {
            test::black_box(grotty2html(&buf));
        });
    }

    #[bench]
    fn bench_rsync(b: &mut test::Bencher) {
        bench_file(b, "t/rsync.1.output");
    }

    #[bench]
    fn bench_ncdu(b: &mut test::Bencher) {
        bench_file(b, "t/ncdu.1.output");
    }

    #[bench]
    fn bench_javadoc(b: &mut test::Bencher) {
        bench_file(b, "t/javadoc.1.output");
    }

    /*
    #[bench]
    fn bench_wfilter(b: &mut test::Bencher) {
        bench_file(b, "t/wfilter.4.output");
    }
    */
}
