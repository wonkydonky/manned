use std::collections::HashSet;
use std::io::BufReader;
use std::str::FromStr;
use std::error::Error;
use std::fmt;
use chrono::NaiveDateTime;
use postgres;
use quick_xml as xml;
use quick_xml::events::Event;

use archive;
use open;
use pkg;
use man;


// Ugh, quick-xml's Error type does not implement Error.
#[derive(Debug)]
struct XmlError(String);
impl fmt::Display for XmlError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result { write!(f, "{}", self.0) }
}
impl Error for XmlError {
    fn description(&self) -> &str { self.0.as_ref() }
}
fn to_err(e: xml::Error) -> XmlError {
    XmlError(format!("{}", e))
}



fn xml_getattr(e: &xml::events::BytesStart, attr: &str) -> Result<String,Box<Error>> {
    for kv in e.attributes().with_checks(false) {
        let kv = kv.map_err(to_err)?;
        if kv.key == attr.as_bytes() {
            return Ok(String::from_utf8(kv.value.into_owned())?);
        }
    }
    Err(Box::new(XmlError(format!("Attribute '{}' not found", attr))))
}


#[derive(Default)]
struct PkgInfo {
    name: Option<String>,
    arch: Option<String>,
    ver: Option<String>,
    date: Option<i64>,
    path: Option<String>,
    hasman: bool,
}


// Shared function to read primary.xml.gz and filelists.xml.gz. Runs the callback for each package
// with the info that was found.
fn readpkgs<F>(url: String, mut cb: F) -> Result<(),Box<Error>>
    where F: FnMut(PkgInfo)
{
    debug!("Reading {}", url);
    let mut fd = open::Path{path: &url, cache: true, canbelocal: false}.open()?;
    let mut xml = xml::Reader::from_reader(
        BufReader::new(
            archive::Archive::open_raw(&mut fd)?
        )
    );
    xml.trim_text(true);

    let mut savestr = false;
    let mut saved = None;
    let mut pkg = PkgInfo::default();
    let mut buf = Vec::new();

    let arch_src = Some("src".to_string());

    loop {
        let event = xml.read_event(&mut buf);
        let event = event.map_err(to_err)?;

        match event {

            Event::Start(ref e) |
            Event::Empty(ref e) =>
                match e.name() {
                    b"name" |
                    b"file" |
                    b"arch"     => savestr  = true,
                    b"version"  => pkg.ver  = Some(format!("{}-{}", xml_getattr(e, "ver")?, xml_getattr(e, "rel")?)),
                    b"location" => pkg.path = Some(xml_getattr(e, "href")?),
                    b"time"     => pkg.date = Some(i64::from_str(&xml_getattr(e, "build")?)?),
                    b"package"  => {
                        pkg.name = xml_getattr(e, "name").ok();
                        pkg.arch = xml_getattr(e, "arch").ok();
                    },
                    _ => (),
                },

            Event::Text(e) =>
                if savestr {
                    saved = Some(e.unescape_and_decode(&xml).map_err(to_err)?);
                    savestr = false
                },

            Event::End(ref e) => {
                savestr = false;
                match e.name() {
                    b"name" => pkg.name = Some(saved.take().unwrap()),
                    b"arch" => pkg.arch = Some(saved.take().unwrap()),
                    b"file" => pkg.hasman = pkg.hasman || man::ismanpath(&saved.take().unwrap()),
                    b"package" => {
                        if pkg.arch != arch_src {
                            cb(pkg);
                        }
                        pkg = PkgInfo::default();
                    },
                    _ => (),
                };
            },

            Event::Eof => break,
            _ => (),
        }
    }
    Ok(())
}


// Reads repomd.xml and returns the path to the primary.xml.gz and filelists.xml.gz
fn repomd(url: String) -> Result<(String,String),Box<Error>> {
    debug!("Reading {}", url);
    let mut fd = open::Path{path: &url, cache: true, canbelocal: false}.open()?;
    let mut xml = xml::Reader::from_reader(
        BufReader::new(
            archive::Archive::open_raw(&mut fd)?
        )
    );
    xml.trim_text(true);

    let mut primary = String::new();
    let mut filelists = String::new();
    let mut datatype = 0;
    let mut buf = Vec::new();

    loop {
        let event = xml.read_event(&mut buf).map_err(to_err)?;
        match event {
            Event::Start(ref e) |
            Event::Empty(ref e) => {
                match e.name() {
                    b"data" =>
                        datatype = match &xml_getattr(e, "type")? as &str {
                            "primary"   => 1,
                            "filelists" => 2,
                            _           => 0,
                        },

                    b"location" =>
                        match datatype {
                            1 => primary   = xml_getattr(e, "href")?,
                            2 => filelists = xml_getattr(e, "href")?,
                            _ => (),
                        },

                    _ => (),
                }
            },
            Event::Eof => break,
            _ => (),
        }
    }
    Ok((primary, filelists))
}


pub fn sync(pg: &postgres::GenericConnection, sys: i32, cat: &str, mirror: &str) -> Result<(),Box<Error>> {
    let(primary, filelists) = repomd(format!("{}repodata/repomd.xml", mirror))?;

    let mut pkgswithman = HashSet::new();
    readpkgs(format!("{}{}", mirror, filelists), |pkg| {
        if pkg.hasman { pkgswithman.insert(pkg.name.unwrap()); () }
    })?;

    readpkgs(format!("{}{}", mirror, primary), |pkg| {
        let name = pkg.name.unwrap();
        if pkgswithman.contains(&name) {
            let uri = format!("{}{}", mirror, pkg.path.unwrap());
            let date = NaiveDateTime::from_timestamp(pkg.date.unwrap(), 0).format("%Y-%m-%d").to_string();
            pkg::pkg(pg, pkg::PkgOpt{
                force: false,
                sys: sys,
                cat: cat,
                pkg: &name,
                ver: &pkg.ver.unwrap(),
                date: pkg::Date::Known(&date),
                arch: Some(&pkg.arch.unwrap()),
                file: open::Path{
                    path: &uri,
                    cache: false,
                    canbelocal: false,
                },
            });
        }
    })?;
    Ok(())
}
