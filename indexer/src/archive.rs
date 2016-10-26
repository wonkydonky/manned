use std::str;
use std::ptr;
use std::error::Error as ErrorTrait;
use std::io::{Result,Error,Read};
use std::ffi::{CStr,CString};

use libc::{c_void,ssize_t};
use libarchive3_sys::ffi;


/* This is a safe, limited and opinionated wrapper around the libarchive C bindings.
 * I initially used the libarchive crate, but it has several issues. Some of which are not fixable
 * without a complete rewrite.
 * - Panics on non-UTF8 path names
 * - Panics on hard links (PR #6)
 * - API is far too flexible, easy to misuse and get panics/segfaults
 * - Impossible to correctly read files from an archive (issue #7)
 * - Does not provide a convenient Read interface for files
 *
 * Barring any unexpected behaviour or bugs in libarchive, the API below should not panic or
 * segfault for any archive or usage pattern.
 */

pub struct Archive<'a> {
    a: *mut ffi::Struct_archive,
    rd: &'a mut Read,
    buf: Vec<u8>,
    err: Option<Error>,
}


pub struct ArchiveEntry<'a> {
    a: Box<Archive<'a>>,
    e: *mut ffi::Struct_archive_entry,
}


#[derive(Debug,PartialEq,Eq)]
pub enum FileType {
    File,
    Directory,
    Link(String),
    Other, // Also includes Link(<non-utf8-path>)
}


unsafe extern "C" fn archive_read_cb(_: *mut ffi::Struct_archive, data: *mut c_void, buf: *mut *const c_void) -> ssize_t {
    let arch: &mut Archive = &mut *(data as *mut Archive);
    *buf = arch.buf.as_mut_ptr() as *mut c_void;
    match arch.rd.read(&mut arch.buf[..]) {
        Ok(s) => s as ssize_t,
        Err(e) => {
            let desc = CString::new(e.description()).unwrap();
            let fmt = CString::new("%s").unwrap();
            ffi::archive_set_error(arch.a, e.raw_os_error().unwrap_or(0), fmt.as_ptr(), desc.as_ptr());
            arch.err = Some(e);
            -1
        }
    }
}


impl<'a> Archive<'a> {
    fn new(rd: &mut Read, a: *mut ffi::Struct_archive) -> Result<Box<Archive>> {
        let bufsize = 64*1024;
        let mut buf = Vec::with_capacity(bufsize);
        unsafe { buf.set_len(bufsize) };
        let mut ret = Box::new(Archive { a: a, rd: rd, buf: buf, err: None });

        let aptr: *mut c_void = &mut *ret as *mut Archive as *mut c_void;
        let r = unsafe { ffi::archive_read_open(a, aptr, None, Some(archive_read_cb), None) };
        if r == ffi::ARCHIVE_FATAL {
            return Err(ret.error());
        }
        Ok(ret)
    }

    fn error(&mut self) -> Error {
        // TODO: Do something with the description
        self.err.take().unwrap_or_else(||
            Error::from_raw_os_error(unsafe { ffi::archive_errno(self.a) })
        )
    }

    fn entry(self: Box<Self>) -> Result<Option<ArchiveEntry<'a>>> {
        let mut ent = ArchiveEntry {
            a: self,
            e: ptr::null_mut()
        };
        let res = unsafe { ffi::archive_read_next_header(ent.a.a, &mut ent.e) };
        match res {
            ffi::ARCHIVE_EOF => Ok(None),
            ffi::ARCHIVE_FATAL => Err(ent.a.error()),
            _ => Ok(Some(ent))
        }
    }

    fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        let cbuf = buf.as_mut_ptr() as *mut c_void;
        let n = unsafe { ffi::archive_read_data(self.a, cbuf, buf.len()) };
        if n >= 0 {
            Ok(n as usize)
        } else {
            Err(self.error())
        }
    }

    pub fn open_archive(rd: &mut Read) -> Result<Option<ArchiveEntry>> {
        let a  = unsafe {
            let a = ffi::archive_read_new();
            ffi::archive_read_support_filter_all(a);
            ffi::archive_read_support_format_all(a);
            a
        };
        try!(Self::new(rd, a)).entry()
    }
}


impl<'a> Drop for Archive<'a> {
    fn drop(&mut self) {
        unsafe {
            ffi::archive_read_free(self.a);
        }
    }
}


impl<'a> ArchiveEntry<'a> {
    pub fn next(self) -> Result<Option<ArchiveEntry<'a>>> {
        self.a.entry()
    }

    // Returns None in NULL (when does that even happen?) or on invalid UTF-8.
    pub fn path(&self) -> Option<&str> {
        let c_str: &CStr = unsafe {
            let ptr = ffi::archive_entry_pathname(self.e);
            if ptr.is_null() {
                return None;
            }
            CStr::from_ptr(ptr)
        };
        str::from_utf8(c_str.to_bytes()).ok()
            // Perform some simple opinionated normalization. Full normalization might be better,
            // but also slower and more complex. This solution covers the most important cases.
            .map(|s| s.trim_left_matches('/').trim_left_matches("./").trim_right_matches('/'))
    }

    pub fn size(&self) -> usize {
        unsafe { ffi::archive_entry_size(self.e) as usize }
    }

    fn symlink(&self) -> Option<String> {
        let c_str: &CStr = unsafe {
            let ptr = ffi::archive_entry_symlink(self.e);
            if ptr.is_null() {
                return None;
            }
            CStr::from_ptr(ptr)
        };
        str::from_utf8(c_str.to_bytes()).map(str::to_string).ok()
    }

    fn hardlink(&self) -> Option<String> {
        let c_str: &CStr = unsafe {
            let ptr = ffi::archive_entry_hardlink(self.e);
            if ptr.is_null() {
                return None;
            }
            CStr::from_ptr(ptr)
        };
        // Hard links have the same name as an earlier pathname(), and those typically don't have a
        // preceding slash. Add this slash here so that the same resolution logic can be used for
        // both hardlinks and symlinks. I really don't care about the difference between these two.
        str::from_utf8(c_str.to_bytes()).map(|p| format!("/{}", p)).ok()
    }

    pub fn filetype(&self) -> FileType {
        // If it has a symlink/hardlink path, then just consider it a link regardless of what
        // _filetype() says.
        if let Some(l) = self.symlink().or(self.hardlink()) {
            return FileType::Link(l);
        }
        match unsafe { ffi::archive_entry_filetype(self.e) } {
            ffi::AE_IFDIR => FileType::Directory,
            ffi::AE_IFREG => FileType::File,
            _ => FileType::Other,
        }
    }
}


impl<'a> Read for ArchiveEntry<'a> {
    fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        self.a.read(buf)
    }
}


// We can't provide an Iterator object for ArchiveEntries because Rust doesn't support streaming
// iterators. Let's instead provide a walk function for convenience.
// cb should return Ok(true) to continue, Ok(false) to break
pub fn walk<F>(ent: Option<ArchiveEntry>, mut cb: F) -> Result<()>
    where F: FnMut(&mut ArchiveEntry) -> Result<bool>
{
    let mut ent = ent;
    while let Some(mut e) = ent {
        if !try!(cb(&mut e)) {
            break;
        }
        ent = try!(e.next());
    }
    Ok(())
}



#[cfg(test)]
mod tests {
    use super::*;
    use std;
    use std::io::Read;
    use std::fs::File;

    #[test]
    fn invalid_archive() {
        let mut r = std::io::repeat(0x0a).take(64*1024);
        let ent = Archive::open_archive(&mut r);
        assert!(ent.is_err());
    }

    #[test]
    fn zerolength_archive() {
        let mut r = std::io::empty();
        let ent = Archive::open_archive(&mut r);
        // I expected an error here rather than None, whatever.
        assert!(ent.unwrap().is_none());
    }

    #[test]
    fn read() {
        let mut f = File::open("tests/simpletest.tar.gz").unwrap();
        let mut ent = Archive::open_archive(&mut f).unwrap().unwrap();

        let t = |e:&mut ArchiveEntry, path, size, ft, cont| {
            assert_eq!(e.path(), path);
            assert_eq!(e.size(), size);
            assert_eq!(e.filetype(), ft);
            let mut contents = String::new();
            assert_eq!(e.read_to_string(&mut contents).unwrap(), size);
            assert_eq!(&contents, cont);
        };

        t(&mut ent, Some("simple"), 0, FileType::Directory, "");

        ent = ent.next().unwrap().unwrap();
        t(&mut ent, Some("simple/file"), 3, FileType::File, "Hi\n");

        ent = ent.next().unwrap().unwrap();
        t(&mut ent, Some("simple/link"), 0, FileType::Link("file".to_string()), "");

        ent = ent.next().unwrap().unwrap();
        t(&mut ent, Some("simple/hardlink"), 0, FileType::Link("/simple/file".to_string()), "");

        ent = ent.next().unwrap().unwrap();
        t(&mut ent, Some("simple/fifo"), 0, FileType::Other, "");

        ent = ent.next().unwrap().unwrap();
        t(&mut ent, None, 0, FileType::File, "");

        assert!(ent.next().unwrap().is_none());
    }
}
