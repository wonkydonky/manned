use std::str::FromStr;
use std::io::{Read,BufRead,BufReader,Result};
use regex::Regex;
use chrono::NaiveDateTime;
use postgres;

use archive;
use open;
use man;
use pkg;


struct Meta {
    filename: String,
    name: String,
    version: String,
    date: String,
    arch: Option<String>,
}


fn read_files<T: Read>(lst: T) -> Result<bool> {
    let rd = BufReader::new(lst);
    for line in rd.lines() {
        let line = try!(line);
        if man::ismanpath(&line) {
            return Ok(true);
        }
    }
    Ok(false)
}


fn read_desc(rd: &mut archive::ArchiveEntry) -> Result<Option<Meta>> {
    let mut data = String::new();
    try!(rd.take(64*1024).read_to_string(&mut data));

    let path = rd.path().unwrap();
    lazy_static! {
        static ref RE: Regex = Regex::new(r"\s*%([^%]+)%\s*\n\s*([^\n]+)\s*\n").unwrap();
    }

    let mut filename = None;
    let mut name = None;
    let mut version = None;
    let mut builddate = None;
    let mut arch = None;

    for kv in RE.captures_iter(&data) {
        let key = kv.at(1).unwrap();
        let val = kv.at(2).unwrap();
        trace!("{}: {} = {}", path, key, val);
        match key {
            "FILENAME"  => filename  = Some(val),
            "NAME"      => name      = Some(val),
            "VERSION"   => version   = Some(val),
            "BUILDDATE" => builddate = i64::from_str(val).ok(),
            "ARCH"      => arch      = Some(val),
            _ => {},
        }
    }

    if filename.is_some() && name.is_some() && version.is_some() && builddate.is_some() {
        Ok(Some(Meta {
            filename: filename.unwrap().to_string(),
            name: name.unwrap().to_string(),
            version: version.unwrap().to_string(),
            date: NaiveDateTime::from_timestamp(builddate.unwrap(), 0).format("%Y-%m-%d").to_string(),
            arch: arch.map(str::to_string),
        }))
    } else {
        warn!("Metadata missing from package description: {}", path);
        Ok(None)
    }
}


pub fn sync(pg: &postgres::GenericConnection, sys: i32, mirror: &str, repo: &str) {
    info!("Reading packages from {} {}", mirror, repo);

    let path = format!("{}/{}/os/x86_64/{1:}.files.tar.gz", mirror, repo);
    let path = open::Path{ path: &path, cache: true, canbelocal: false };
    let mut index = match path.open() {
        Err(e) => { error!("Can't read package index: {}", e); return },
        Ok(x) => x,
    };

    let ent = match archive::Archive::open_archive(&mut index) {
        Err(e) => { error!("Can't read package index: {}", e); return },
        Ok(x) => x,
    };

    let mut hasman = false;
    let mut meta = None;
    let r = archive::walk(ent, |x| {
        if x.filetype() == archive::FileType::Directory {
            hasman = false;
            meta = None;
        } else if x.path().unwrap().ends_with("/files") {
            hasman = try!(read_files(x));
        } else if x.path().unwrap().ends_with("/desc") {
            meta = try!(read_desc(x));
        }

        if hasman && meta.is_some() {
            hasman = false;
            let m = meta.take().unwrap();

            let p = format!("{}/{}/os/x86_64/{}", mirror, repo, m.filename);
            pkg::pkg(pg, pkg::PkgOpt{
                force: false,
                sys: sys,
                cat: repo,
                pkg: &m.name,
                ver: &m.version,
                date: &m.date,
                arch: m.arch.as_ref().map(|e| &e[..]),
                file: open::Path{
                    path: &p,
                    cache: false,
                    canbelocal: false,
                },
            });
        }

        Ok(true)
    });

    if let Err(e) = r {
        error!("Error reading package index: {}", e);
    }
}
