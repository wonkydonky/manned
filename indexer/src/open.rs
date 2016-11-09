use std::io::{Read,Result,Error,ErrorKind,copy};
use std::fs::{File,create_dir_all,metadata};
use std::hash::{Hash,Hasher,SipHasher};
use std::time::{Duration,SystemTime};
use url::Url;
use hyper;


const CACHE_PATH: &'static str = "/var/tmp/manned-indexer";
const CACHE_TIME: u64 = 23*3600;


pub struct Path<'a> {
    pub path: &'a str,
    pub cache: bool,
    pub canbelocal: bool,
}


fn cache_fn(url: &Url) -> String {
    let name = url.path_segments().unwrap().last().unwrap();
    let name = if name == "" { "index" } else { name };

    let mut hash = SipHasher::new();
    url.hash(&mut hash);
    format!("{}/{}-{}-{:x}", CACHE_PATH, url.host_str().unwrap(), name, hash.finish())
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


impl<'a> Path<'a> {
    pub fn open(&self) -> Result<Box<Read>> {
        if let Ok(url) = Url::parse(self.path) {
            if url.scheme() != "http" && url.scheme() != "https" {
                return Err(Error::new(ErrorKind::Other, "Invalid scheme"));
            }

            if self.cache {
                let cfn = cache_fn(&url);
                if let Ok(m) = metadata(&cfn) {
                    if m.modified().unwrap() > SystemTime::now() - Duration::from_secs(CACHE_TIME) {
                        return file(&cfn);
                    }
                }
                try!(create_dir_all(CACHE_PATH));
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
}
