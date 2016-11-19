use std::io::{Result,BufReader,BufRead};
use std::collections::HashSet;
use std::str;
use postgres;
use regex::bytes::Regex;

use man;
use pkg;
use open;
use archive;

// Reference: https://wiki.debian.org/RepositoryFormat

fn get_contents(f: open::Path) -> Result<HashSet<String>> {
    let mut fd = f.open()?;
    let rd = archive::Archive::open_raw(&mut fd)?;
    let brd = BufReader::new(rd);
    let mut pkgs = HashSet::new();
    let mut filecnt = 0;
    let mut mancnt = 0;

    // Run the regex on bytes instead of strings, as paths aren't always UTF-8. This regex will
    // not match non-UTF-8 paths.
    let re = Regex::new(r"^(?u:([^\s].*?))\s+(?u:([^\s]+))\s*$").unwrap();

    for line in brd.split(b'\n') {
        re.captures(&line?).map(|cap| {
            filecnt += 1;
            let path = str::from_utf8(cap.at(1).unwrap()).unwrap();
            if man::ismanpath(path) {
                mancnt += 1;
                pkgs.extend( str::from_utf8(cap.at(2).unwrap()).unwrap().split(',').map(|e| {
                    e.split('/').last().unwrap().to_string()
                }) );
            }
        });
    }

    debug!("Found {}/{} man files in {} relevant packages from {}", mancnt, filecnt, pkgs.len(), f.path);
    Ok(pkgs)
}


#[derive(Default)]
struct Pkg {
    name: Option<String>,
    section: Option<String>,
    arch: Option<String>,
    version: Option<String>,
    filename: Option<String>,
}


fn handlepkg(pg: &postgres::GenericConnection, sys: i32, mirror: &str, manpkgs: &HashSet<String>, pkg: &Pkg) {
    let name     = match pkg.name     { Some(ref x) => x, None => return };
    if !manpkgs.contains(name) {
        return
    }
    let section  = match pkg.section  { Some(ref x) => x, None => { error!("Package {} has no section",  name); return } };
    let arch     = match pkg.arch     { Some(ref x) => x, None => { error!("Package {} has no arch",     name); return } };
    let version  = match pkg.version  { Some(ref x) => x, None => { error!("Package {} has no version",  name); return } };
    let filename = match pkg.filename { Some(ref x) => x, None => { error!("Package {} has no filename", name); return } };
    let uri = format!("{}{}", mirror, filename);

    pkg::pkg(pg, pkg::PkgOpt{
        force: false,
        sys: sys,
        cat: &section,
        pkg: &name,
        ver: &version,
        date: "1980-01-01", // TODO: Fetch date from somewhere (package contents itself, likely)
        arch: Some(arch),
        file: open::Path{
            path: &uri,
            cache: false,
            canbelocal: false,
        },
    });
}


pub fn sync(pg: &postgres::GenericConnection, sys: i32, mirror: &str, contents: open::Path, packages: open::Path) {
    let manpkgs = match get_contents(contents) {
        Err(e) => { error!("Can't read {}: {}", contents.path, e); return },
        Ok(x) => x,
    };

    let mut fd = match packages.open() {
        Err(e) => { error!("Can't read {}: {}", packages.path, e); return },
        Ok(x) => x,
    };
    let rd = match archive::Archive::open_raw(&mut fd) {
        Err(e) => { error!("Can't read {}: {}", packages.path, e); return },
        Ok(x) => x,
    };

    let brd = BufReader::new(rd);
    let mut pkg = Pkg::default();
    let emptyline = Regex::new(r"^\s*$").unwrap();
    let kv = Regex::new(r"^(?u:([^#-][^ :]*)\s*:\s*(.+))$").unwrap();

    for line in brd.split(b'\n') {
        let line = match line {
            Err(e) => { error!("Can't read {}: {}", packages.path, e); return },
            Ok(x) => x,
        };
        if emptyline.is_match(&line) {
            handlepkg(pg, sys, &mirror, &manpkgs, &pkg);
            pkg = Pkg::default();
        }
        if let Some(cap) = kv.captures(&line) {
            let val = str::from_utf8(cap.at(2).unwrap()).unwrap();
            match str::from_utf8(cap.at(1).unwrap()).unwrap() {
                "Package" => pkg.name = Some(val.to_string()),
                "Section" => pkg.section = Some(val.to_string()),
                "Version" => pkg.version = Some(val.to_string()),
                "Architecture" => pkg.arch = Some(val.to_string()),
                "Filename" => pkg.filename = Some(val.to_string()),
                _ => {}
            }
        }
    }
    handlepkg(pg, sys, &mirror, &manpkgs, &pkg);
}
