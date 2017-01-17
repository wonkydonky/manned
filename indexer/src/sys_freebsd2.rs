use std::io::{BufReader,BufRead,Result,Error,ErrorKind};
use regex::bytes::Regex;
use std::str;
use postgres;

use open;
use pkg;
use archive::{Archive,ArchiveEntry};


fn getpkgsite(mut ent: Option<ArchiveEntry>) -> Result<ArchiveEntry> {
    while let Some(e) = ent {
        if e.path() == Some("packagesite.yaml") {
            return Ok(e)
        }
        ent = e.next()?
    }
    Err(Error::new(ErrorKind::Other, "No packagesite.yaml found"))
}


pub fn sync(pg: &postgres::GenericConnection, sys: i32, mirror: &str) -> Result<()> {
    let path = format!("{}packagesite.txz", mirror);
    let mut rd = open::Path{path: &path, cache: true, canbelocal: false}.open()?;

    let ent = Archive::open_archive(&mut rd)?;
    let brd = BufReader::new(getpkgsite(ent)?);

    // It's technically a JSON/YAML file, but rather than bothering with a proper JSON parser,
    // these regexes will do fine.
    lazy_static!(
        static ref RE_NAME : Regex = Regex::new(r#""name"\s*:\s*"(?u:([^ "]+))""#).unwrap();
        static ref RE_VER  : Regex = Regex::new(r#""version"\s*:\s*"(?u:([^ "]+))""#).unwrap();
        static ref RE_CAT  : Regex = Regex::new(r#""origin"\s*:\s*"(?u:([^ "/]+))"#).unwrap();
        static ref RE_PATH : Regex = Regex::new(r#""path"\s*:\s*"(?u:([^ "]+))""#).unwrap();
        static ref RE_ARCH : Regex = Regex::new(r#""arch"\s*:\s*"(?u:([^ "]+))""#).unwrap();
    );

    for line in brd.split(b'\n') {
        let line = line?;
        let name = match RE_NAME.captures(&line) { None => continue, Some(c) => str::from_utf8(c.get(1).unwrap().as_bytes()).unwrap() };
        let ver  = match RE_VER .captures(&line) { None => continue, Some(c) => str::from_utf8(c.get(1).unwrap().as_bytes()).unwrap() };
        let cat  = match RE_CAT .captures(&line) { None => continue, Some(c) => str::from_utf8(c.get(1).unwrap().as_bytes()).unwrap() };
        let path = match RE_PATH.captures(&line) { None => continue, Some(c) => str::from_utf8(c.get(1).unwrap().as_bytes()).unwrap() };
        let arch = match RE_ARCH.captures(&line) { None => continue, Some(c) => str::from_utf8(c.get(1).unwrap().as_bytes()).unwrap() };
        let uri = format!("{}{}", mirror, path);
        pkg::pkg(pg, pkg::PkgOpt{
            force: false,
            sys: sys,
            cat: cat,
            pkg: name,
            ver: ver,
            date: pkg::Date::Max,
            arch: Some(arch),
            file: open::Path{
                path: &uri,
                cache: false,
                canbelocal: false,
            },
        });
    }
    Ok(())
}
