use std::io::{BufRead,BufReader,Read,Result,Error,ErrorKind,copy};
use std::fs::{File,create_dir_all,metadata,read_dir,remove_file};
use std::time::{Duration,SystemTime};
use regex::bytes::Regex;
use ring::digest;
use url::Url;
use url::percent_encoding::percent_decode;
use hyper;


const CACHE_PATH: &'static str = "/var/tmp/manned-indexer";
const CACHE_TIME: u64 = 20*3600;


#[derive(Clone,Copy)]
pub struct Path<'a> {
    pub path: &'a str,
    pub cache: bool,
    pub canbelocal: bool,
}


fn cache_fn(url: &Url) -> String {
    let name = url.path_segments().unwrap().last().unwrap();
    let name = if name == "" { "index" } else { name };

    let hash = digest::digest(&digest::SHA1, url.as_str().as_bytes())
        .as_ref()[0..8].into_iter()
        .fold(0u64, |a, &e| (a<<8) + e as u64);

    format!("{}/{}-{}-{:x}", CACHE_PATH, url.host_str().unwrap(), name, hash)
}


fn fetch(url: &str) -> Result<Box<Read>> {
    let res = try!(hyper::Client::new()
        .get(url)
        .header(hyper::header::UserAgent("Man page crawler (info@manned.org; https://manned.org/)".to_owned()))
        .send()
        .map_err(|e| Error::new(ErrorKind::Other, format!("Hyper: {}", e)))
    );
    if !res.status.is_success() {
        return Err(Error::new(ErrorKind::Other, format!("HTTP: {}", res.status) ));
    }
    Ok(Box::new(res) as Box<Read>)
}


fn file(path: &str) -> Result<Box<Read>> {
    Ok(Box::new(try!(File::open(path))) as Box<Read>)
}


pub fn clear_cache() -> Result<()> {
    create_dir_all(CACHE_PATH)?;
    for f in read_dir(CACHE_PATH)? {
        let f = f?.path();
        let m = metadata(&f)?;
        if m.modified().unwrap() < SystemTime::now() - Duration::from_secs(CACHE_TIME) {
            remove_file(&f)?;
        }
    }
    Ok(())
}


impl<'a> Path<'a> {
    pub fn open(&self) -> Result<Box<Read>> {
        if let Ok(url) = Url::parse(self.path) {
            if url.scheme() != "http" {
                return Err(Error::new(ErrorKind::Other, "Invalid scheme"));
            }

            if self.cache {
                let cfn = cache_fn(&url);
                if let Ok(f) = file(&cfn) {
                    return Ok(f);
                }
                {
                    let mut rd = try!(fetch(url.as_str()));
                    let mut wr = try!(File::create(&cfn));
                    try!(copy(&mut rd, &mut wr));
                }
                file(&cfn)

            } else {
                fetch(url.as_str())
            }

        } else if self.canbelocal {
            file(self.path)

        } else {
            Err(Error::new(ErrorKind::Other, "Invalid URL"))
        }
    }

    // Attempt to parse a HTTP directory listing. Returns the name and whether it's a directory for
    // each item.
    // Only tested with a lighttpd/1.4 and apache 2.4 server.
    // (I tried using FTP before, but that didn't work out well; While FTP does return a more easily
    // parsable file list, some servers have issues with generating a list of a large directory)
    pub fn dirlist(&self) -> Result<Vec<(String,bool)>> {
        lazy_static!(
            static ref RE: Regex = Regex::new("(?i:<a +href *= *\"([^?/\"]+)(/)?\">)").unwrap();
        );
        let rd = self.open()?;
        let brd = BufReader::new(rd);
        let mut res = Vec::new();
        for line in brd.split(b'\n') {
            let line = line?;
            let mut matches = RE.captures_iter(&line);
            let first = matches.next();

            // There's only a single link per line.
            if first.is_some() && matches.next().is_some() {
                continue;
            }

            if let Some(cap) = first {
                let name = &cap[1];
                if name == b".." || name.starts_with(b"/") {
                    continue;
                }
                if let Ok(name) = percent_decode(name).decode_utf8() {
                    let isdir = cap.get(2).is_some();
                    res.push((name.to_string(), isdir));
                }
            }
        }
        Ok(res)
    }

}
