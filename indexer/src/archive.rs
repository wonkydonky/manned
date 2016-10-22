use std::path::Path;
use std::collections::HashMap;
use libarchive::reader::Reader as ArchiveReader;
use libarchive::reader::{FileReader,Builder};
use libarchive::archive::{Entry,FileType,ReadFormat,ReadFilter};
use libarchive::error::ArchiveResult;


pub fn open_file<T: AsRef<Path>>(path: T) -> ArchiveResult<FileReader> {
    let mut builder = Builder::new();
    try!(builder.support_format(ReadFormat::All));
    try!(builder.support_filter(ReadFilter::All));
    builder.open_file(path)
}


#[derive(Clone,Debug,PartialEq,Eq)]
pub enum EntryType {
    // Regular file that has been handled/indexed
    Handled,
    // Regular file that hasn't been handled because the caller wasn't interested in it. Could
    // still be an interesting file if it is referenced from an interesting path.
    Regular,
    // Link to another file (interesting or not is irrelevant)
    Link(String),
    // Directory; need this information when resolving links
    Directory,
    // Something that couldn't be a an interesting file (chardev/socket/etc); If any link resolves
    // to this we know we're done.
    Other,
}


/*
 * I had hoped that reading man pages from an archive would just be a simple:
 *
 * 1. Walk through all files in the archive in a streaming fashion
 * 2. Parse/index man pages
 *
 * But alas, it was not to be. Symlinks and hardlinks have ruined it. Now we have to...
 *
 * 1. Walk through all entries in the archive in a streaming fashion
 * 2. Parse/index regular file man pages
 * 3. Keep track of all paths in the archive
 * 4. Use the result of step (3) to resolve symlinks/hardlinks to their actual file
 * 5. Read the entire damn archive again if one of the links resolved to a file that was not
 *    recognized as a man page in step (2). Luckily, this isn't very common.
 *
 * And this doesn't even cover the problem of duplicate entries in a tar, which is also quite
 * annoying to handle.
 *
 * What annoys me the most about all of this is that it's not possible to stream an archive from
 * the network and read/index the entire thing in a single step. Now we have to buffer packages to
 * disk in order to be able to read the archive a second time.
 *
 * (Note that it is possible to resolve links while walking through the entries, which will allow
 * us to match files found later in the archive against links found earlier, thus potentially
 * saving the need to read the archive a second time. This is merely a performance improvement for
 * an uncommon case, and it certainly won't simplify the code)
 *
 * (Note that it's also possible to just flush all files <10MB* to disk to completely avoid the
 * need for a second archive read, but that's going to significantly slow down the common case in
 * order to handle a rare case. It's possible to further optimize this using some heuristics to
 * determine whether a file is potentially a man page, but that's both complex and may not even
 * save much)
 *
 * (* So apparently some man pages are close to 10MB...)
 */
pub struct Reader {
    // List of seen files. This is used to resolve links
    seen: HashMap<String, EntryType>,
    // List of interesting links
    links: Vec<String>,
    // List of files we have to read in a second walk through the archive
    missedfiles: HashMap<String, Vec<String>>,
}


// Generalized API:
// 1. Read once
//    reader.read(file, interest_cb, file_cb) -> Error
//    file: A libarchive::Reader
//    interest_cb(path) -> bool
//      Called on every file/link name, should return whether it's a file the caller is interested
//      in.  (e.g. parse_path(), but also +DESC and other metadata).
//    file_cb(path, reader, entry) -> Error
//      Called on every interesting (actual) file, given the (normalized?) path, the
//      libarchive::Reader and a ReaderEntry
//
// 2. Read links
//    reader.links(link_cb) -> Error
//    link_cb(path, dest) -> Error
//      Called on every link which has as 'dest' a file path that has already been given to
//      file_cb() before.
//
// 3. (Optionally) read a second time
//    if reader.need_reread() {
//      reader.reread(file, file_cb)
//    }
impl Reader {
    pub fn new() -> Reader {
        Reader {
            seen: HashMap::new(),
            links: Vec::new(),
            missedfiles: HashMap::new(),
        }
    }

    // Convenience function to read the path/type/link from the next header.
    fn read_header(rd: &mut ArchiveReader) -> Option<(String, EntryType)> {
        let ent = match rd.next_header() {
            Some(x) => x,
            None => return None,
        };
        let path = ent.pathname().trim_left_matches('/').trim_left_matches("./").trim_right_matches('/').to_string();

        // Hard links are apparently relative to the root of the archive.
        let link = ent.hardlink().map(|x| format!("/{}", x))
            .or(ent.symlink().map(str::to_string));

        let(fts, ret) = match ent.filetype() {
            FileType::BlockDevice     => ("blk", EntryType::Other),
            FileType::SymbolicLink    => ("sym", match link { Some(l) => EntryType::Link(l), _ => EntryType::Other }),
            FileType::Socket          => ("sck", EntryType::Other),
            FileType::CharacterDevice => ("chr", EntryType::Other),
            FileType::Directory       => ("dir", EntryType::Directory),
            FileType::NamedPipe       => ("fif", EntryType::Other),
            FileType::Mount           => ("mnt", EntryType::Other),
            FileType::RegularFile     => ("reg", EntryType::Regular),
            FileType::Unknown         => ("unk", match link { Some(l) => EntryType::Link(l), _ => EntryType::Other }),
        };

        trace!("Archive entry: {}{:10} bytes, path={:?} type={:?}", fts, ent.size(), path, ret);
        Some((path, ret))
    }

    pub fn read<F,G>(&mut self, rd: &mut ArchiveReader, interest_cb: F, mut file_cb: G) -> ArchiveResult<()>
        where F: Fn(&str) -> bool, G: FnMut(&[&str], &mut ArchiveReader) -> ArchiveResult<()>
    {
        while let Some((path, t)) = Self::read_header(rd) {
            // We ought to throw away the result of the previous entry with the same name and use
            // this new entry instead, but fuck it. This case is too rare, so let's just warn! it.
            if let Some(_) = self.seen.get(&path) {
                warn!("Duplicate file entry: {}", path);
                continue;
            }

            let mut newt = t;
            match newt {
                EntryType::Regular if interest_cb(&path) => {
                    let pathv = [&path as &str];
                    try!(file_cb(&pathv[..], rd));
                    newt = EntryType::Handled
                },
                EntryType::Link(_) if interest_cb(&path) => {
                    self.links.push(path.clone());
                },
                _ => ()
            };
            self.seen.insert(path, newt);
        }
        Ok(())
    }

    // This is basically realpath(), using the virtual filesystem in self.seen.
    // This method is not particularly efficient, it allocates like crazy.
    fn resolve_link(&self, base: &str, path: &str, depth: usize) -> Option<(EntryType, Vec<String>)> {
        if depth < 1 {
            warn!("Unresolved link: {} -> {}; Recursion depth exceeded", base, path);
            return None
        }

        // Remove filename from the base
        let basedir = if let Some(i) = base.rfind('/') { base.split_at(i).0 } else { return None };

        let comp : Vec<&str> =
            if path.starts_with('/') { path.split('/').collect() }
            else { basedir.split('/').chain(path.split('/')).collect() };

        let mut dest = Vec::new();

        for (i, &c) in comp.iter().enumerate() {
            if c == "" || c == "." {
                continue;
            }
            if c == ".." {
                if dest.len() > 1 {
                    dest.pop();
                }
                continue;
            }
            dest.push(c.to_string());
            let curpath = dest.join("/");
            match self.seen.get(&curpath) {

                // If it's a directory, we're good
                Some(&EntryType::Directory) => (),

                // If it's a file or man page, it must be the last item.
                Some(& ref x@ EntryType::Regular) |
                Some(& ref x@ EntryType::Handled) => return
                    if i == comp.len()-1 {
                        Some((x.clone(), dest))
                    } else {
                        warn!("Unresolved link: {} -> {}; Non-directory component", base, path);
                        None
                    },

                // Links... Ugh
                Some(&EntryType::Link(ref d)) => {
                    match self.resolve_link(&curpath, &d, depth-1) {
                        // Same as above, with dirs we can continue, files have to be last
                        Some((EntryType::Directory, d)) => dest = d,
                        x@Some((EntryType::Regular, _)) |
                        x@Some((EntryType::Handled, _)) => return
                            if i == comp.len()-1 { x }
                            else {
                                warn!("Unresolved link: {} -> {}; Non-directory link component", base, path);
                                None
                            },
                        _ => return None,
                    }
                },

                // Don't care about anything else, just stop.
                _ => {
                    warn!("Unresolved link: {} -> {}; Special or non-existing file", base, path);
                    return None
                }
            }
        }
        Some((EntryType::Directory, dest))
    }

    pub fn links<F>(&mut self, mut cb: F) where F: FnMut(&str, &str) {
        for p in self.links.iter() {
            let dest = match self.seen.get(p) { Some(&EntryType::Link(ref x)) => x, _ => unreachable!() };

            match self.resolve_link(&p, dest, 32) {
                Some((EntryType::Handled, d)) => {
                    let dstr = d.join("/");
                    cb(&p, &dstr)
                },
                Some((EntryType::Regular, d)) => {
                    let dstr = d.join("/");
                    self.missedfiles.entry(dstr).or_insert_with(Vec::new).push(p.to_string());
                }
                _ => {},
            }
        }
        // We can reclaim this memory early.
        self.links = Vec::new();
        self.seen = HashMap::new();
    }

    pub fn need_reread(&self) -> bool {
        self.missedfiles.len() > 0
    }

    pub fn reread<G>(&mut self, rd: &mut ArchiveReader, mut file_cb: G) -> ArchiveResult<()>
        where G: FnMut(&[&str], &mut ArchiveReader) -> ArchiveResult<()>
    {
        while let Some((path, _)) = Self::read_header(rd) {
            if let Some(f) = self.missedfiles.remove(&path) {
                let v: Vec<&str> = f.iter().map(|x| x as &str).collect();
                try!(file_cb(&v, rd))
            }
            if self.missedfiles.len() < 1 {
                break;
            }
        }
        Ok(())
    }
}




#[cfg(test)]
mod tests {
    use super::*;
    use env_logger;

    fn test_read(r: &mut Reader) {
        let mut f = open_file("tests/testarchive.tar.xz").unwrap();
        let mut files = Vec::new();
        r.read(&mut f,
            |p| p.starts_with("man/man"),
            |p,_| { files.extend(p.iter().map(|x| x.to_string())); Ok(()) }
        ).unwrap();
        assert_eq!(files, vec!["man/man3/helloworld.3".to_string()]);
    }

    fn test_resolve_links(r: &mut Reader) {
        let res = |p| {
            if let Some(&EntryType::Link(ref l)) = r.seen.get(p) {
                r.resolve_link(p, &l, 5)
            } else {
                panic!("Not found or not a link: {}", p);
            }
        };
        let helloworld = Some((EntryType::Handled, vec!["man".to_string(), "man3".to_string(), "helloworld.3".to_string()]));

        assert_eq!(res("man/mans"), Some((EntryType::Directory, vec!["man".to_string(), "man3".to_string()])));
        assert_eq!(res("man/man6/hardlink.6"), helloworld);
        assert_eq!(res("man/man1/symlinkbefore.1"), helloworld);
        assert_eq!(res("man/man6/symlinkafter.6"), helloworld);

        assert_eq!(res("man/man1/badsymlink1.1"), None);
        assert_eq!(res("man/man1/badsymlink2.1"), None);
        assert_eq!(res("man/man1/badsymlink3.1"), None);
        assert_eq!(res("man/man1/badsymlink4.1"), None);
        assert_eq!(res("man/man1/badsymlink5.1"), None);

        assert_eq!(res("man/man1/doublesymlink1.1"), helloworld);
        assert_eq!(res("man/man1/doublesymlink2.1"), helloworld);
        assert_eq!(res("man/man1/triplesymlink.1"), helloworld);
        assert_eq!(res("man/man1/infinitesymlink.1"), None);
    }

    fn test_links(r: &mut Reader) {
        let mut links = Vec::new();
        r.links(|p,d| links.push((p.to_string(), d.to_string())));
        links.sort();

        {
            let mut res = |p:&str| {
                let r = links.remove(0);
                assert_eq!(r.0, p.to_string());
                assert_eq!(r.1, "man/man3/helloworld.3".to_string());
            };
            res("man/man1/doublesymlink1.1");
            res("man/man1/doublesymlink2.1");
            res("man/man1/symlinkbefore.1");
            res("man/man1/triplesymlink.1");
            res("man/man6/hardlink.6");
            res("man/man6/symlinkafter.6");
        }
        assert_eq!(links.len(), 0);
    }

    fn test_reread(r: &mut Reader) {
        assert!(r.need_reread());

        let mut f = open_file("tests/testarchive.tar.xz").unwrap();
        let mut files = Vec::new();
        r.reread(&mut f,
            |p,_| { files.extend(p.iter().map(|x| x.to_string())); Ok(()) }
        ).unwrap();

        files.sort();
        assert_eq!(files, vec![
            "man/man3/needreread.3".to_string(),
            "man/man6/needreread.6".to_string()
        ]);
    }

    #[test]
    fn test_reader() {
        env_logger::init().unwrap();

        let mut r = Reader::new();
        test_read(&mut r);
        test_resolve_links(&mut r);
        test_links(&mut r);
        test_reread(&mut r);
    }
}
