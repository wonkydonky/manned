use std::io::Result;
use std::collections::HashMap;

use archive::{walk,ArchiveEntry,FileType};

/* I had hoped that reading man pages from an archive would just be a simple:
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
 * the network and read/index the entire thing in a single step. Now we either have to buffer
 * packages to disk or redownload the archive in order to be able to follow all links to man pages.
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
    // Something that couldn't be an interesting file (chardev/socket/etc); If any link resolves to
    // this we know we're done.
    Other,
}

pub struct FileList {
    // List of seen files. This is used to resolve links
    seen: HashMap<String, EntryType>,
    // List of interesting links
    links: Vec<String>,
}

pub struct MissedFiles(HashMap<String, Vec<String>>);


impl FileList {

    /* Read an archive until the end. Accepts two callbacks:
     *
     *   interest_cb: Called on every path in the archive, should return whether the file is
     *       interesting (i.e. whether we want to know its contents).
     *   file_cb: Called on every regular file for which interest_cb() showed an interest.
     *       The callback accepts multiple path names, but this function will only provide one.
     *
     * Returns a FileList struct that can be used to retreive all interesting non-regular files.
     */
    pub fn read<F,G>(ent: Option<ArchiveEntry>, interest_cb: F, mut file_cb: G) -> Result<FileList>
        where F: Fn(&str) -> bool, G: FnMut(&[&str], &mut ArchiveEntry) -> Result<()>
    {
        let mut fl = FileList {
            seen: HashMap::new(),
            links: Vec::new(),
        };

        try!(walk(ent, |mut e| {
            let path = match e.path() {
                Some(x) => x.to_string(),
                None => { warn!("Invalid UTF-8 filename in archive"); return Ok(true) }
            };
            let ft = e.filetype();
            trace!("Archive entry: {:10} {} {:?}", e.size(), path, ft);

            // We ought to throw away the result of the previous entry with the same name and use
            // this new entry instead, but fuck it. This case is too rare, so let's just warn.
            if let Some(_) = fl.seen.get(&path) {
                warn!("Duplicate file entry: {}", path);
                return Ok(true);
            }

            let et = match ft {
                FileType::File => {
                    if interest_cb(&path) {
                        let pathv = [&path as &str];
                        try!(file_cb(&pathv[..], &mut e));
                        EntryType::Handled
                    } else {
                        EntryType::Regular
                    }
                },
                FileType::Link(l) => {
                    if interest_cb(&path) {
                        fl.links.push(path.clone());
                    }
                    EntryType::Link(l)
                },
                FileType::Directory => EntryType::Directory,
                FileType::Other => EntryType::Other,
            };

            fl.seen.insert(path, et);
            Ok(true)
        }));
        Ok(fl)
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

    /* Calls cb() on every 'interesting' link to a file that has already been passed to a file_cb()
     * in FileList::read().
     * If there are any interesting links that have not yet been passed to file_cb(), a MissedFiles
     * struct is returned that can be used to retrieve those files by re-reading the archive.
     */
    pub fn links<F>(self, mut cb: F) -> Option<MissedFiles> where F: FnMut(&str, &str) {
        let mut missed = HashMap::new();

        for p in self.links.iter() {
            let dest = match self.seen.get(p) { Some(&EntryType::Link(ref x)) => x, _ => unreachable!() };

            match self.resolve_link(&p, dest, 32) {
                Some((EntryType::Handled, d)) => {
                    let dstr = d.join("/");
                    cb(&p, &dstr);
                },
                Some((EntryType::Regular, d)) => {
                    let dstr = d.join("/");
                    missed.entry(dstr).or_insert_with(Vec::new).push(p.to_string());
                }
                _ => (),
            }
        }

        if missed.len() > 0 {
            Some(MissedFiles(missed))
        } else {
            None
        }
    }
}


impl MissedFiles {
    /* Reads the archive again and calls file_cb() on every interesting file that was missed during
     * the first read of the archive (using FileList::{read,links}). file_cb is exactly the same as
     * in FileList::read, but this time it can actually get multiple paths as first argument; which
     * happens when multiple interesting links point to the same file. */
    pub fn read<G>(mut self, ent: Option<ArchiveEntry>, mut file_cb: G) -> Result<()>
        where G: FnMut(&[&str], &mut ArchiveEntry) -> Result<()>
    {
        walk(ent, |mut e| {
            if let Some(f) = e.path().and_then(|p| self.0.remove(p)) {
                let v: Vec<&str> = f.iter().map(|x| x as &str).collect();
                try!(file_cb(&v, &mut e))
            }
            Ok(self.0.len() > 0)
        })
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use archive::Archive;
    use std::io::Read;
    use std::fs::File;

    fn test_read() -> FileList {
        let mut f = File::open("tests/testarchive.tar.xz").unwrap();
        let arch = Archive::open_archive(&mut f).unwrap();
        let mut cnt = 0;
        FileList::read(arch,
            |p| p.starts_with("man/man"),
            |p,e| {
                assert_eq!(cnt, 0);
                cnt += 1;
                assert_eq!(p, &["man/man3/helloworld.3"][..]);
                assert_eq!(e.size(), 12);

                let mut cont = String::new();
                e.read_to_string(&mut cont).unwrap();
                assert_eq!(&cont, "Hello World\n");
                Ok(())
            }
        ).unwrap()
    }

    fn test_resolve_links(r: &FileList) {
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

    fn test_links(r: FileList) -> Option<MissedFiles> {
        let mut links = Vec::new();
        let missed = r.links(|p,d| links.push((p.to_string(), d.to_string())));
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
        missed
    }

    fn test_reread(r: MissedFiles) {
        let mut f = File::open("tests/testarchive.tar.xz").unwrap();
        let ent = Archive::open_archive(&mut f).unwrap();
        let mut files = Vec::new();
        r.read(ent,
            |p,e| {
                let mut cont = String::new();
                e.read_to_string(&mut cont).unwrap();
                files.extend(p.iter().map(|x| (x.to_string(), cont.clone()) ));
                Ok(())
            }
        ).unwrap();
        files.sort();

        {
            let mut res = |a:&str, b:&str| {
                let r = files.remove(0);
                assert_eq!(&r.0, a);
                assert_eq!(&r.1, b);
            };
            res("man/man3/needreread.3", "Potentially interesting file\n");
            res("man/man6/needreread.6", "Potentially interesting file\n");
        }
        assert_eq!(files.len(), 0);
    }

    #[test]
    fn test_reader() {
        //use env_logger;
        //env_logger::init().unwrap();

        let r = test_read();
        test_resolve_links(&r);
        let l = test_links(r).unwrap();
        test_reread(l);
    }
}
