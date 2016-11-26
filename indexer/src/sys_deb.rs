use std::io::{Result,BufReader,BufRead};
use std::collections::HashSet;
use std::str;
use postgres;
use regex;
use regex::bytes::Regex;

use man;
use pkg;
use open;
use archive;

// Reference: https://wiki.debian.org/RepositoryFormat

fn get_contents(f: Option<open::Path>) -> Result<HashSet<String>> {
    let f = match f { Some(f) => f, None => return Ok(HashSet::new()) };
    let mut fd = f.open()?;
    let rd = archive::Archive::open_raw(&mut fd)?;
    let brd = BufReader::new(rd);
    let mut pkgs = HashSet::new();
    let mut filecnt = -1;
    let mut mancnt = 0;

    for line in brd.split(b'\n') {
        let line = line?;
        let line = match str::from_utf8(&line) { Ok(x) => x, _ => continue };
        if line.starts_with("FILE  ") {
            filecnt = 0;
            continue;
        } else if filecnt < 0 {
            continue;
        }
        filecnt += 1;
        let mut it = line.split(' ');
        let pkg = it.next_back().unwrap();
        let path = it.fold(String::new(), |acc, x| acc + " " + x);
        if man::ismanpath(&path.trim()) {
            mancnt += 1;
            pkgs.extend( pkg.split(',').map(|e| {
                e.split('/').last().unwrap().to_string()
            }) );
        }
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
    if manpkgs.len() > 0 && !manpkgs.contains(name) {
        return
    }
    let section  = match pkg.section  { Some(ref x) => x, None => { error!("Package {} has no section",  name); return } };
    let version  = match pkg.version  { Some(ref x) => x, None => { error!("Package {} has no version",  name); return } };
    let filename = match pkg.filename { Some(ref x) => x, None => { error!("Package {} has no filename", name); return } };

    // Workarounds for some bad repos
    let uri = if sys == 18 || sys == 19 {
        let filename = regex::Regex::new("^(Debian-1.[12])/").unwrap().replace(filename, "dists/$1/main/");
        if filename.starts_with("contrib/") {
            format!("{}dists/Debian-1.{}/{}", mirror, if sys == 18 { 1 } else { 2 }, filename)
        } else {
            format!("{}{}", mirror, filename)
        }
    } else {
        format!("{}{}", mirror, filename)
    };

    pkg::pkg(pg, pkg::PkgOpt{
        force: false,
        sys: sys,
        cat: &section,
        pkg: &name,
        ver: &version,
        date: pkg::Date::Deb,
        arch: pkg.arch.as_ref().map(|e| &e[..]),
        file: open::Path{
            path: &uri,
            cache: false,
            canbelocal: false,
        },
    });
}


pub fn sync(pg: &postgres::GenericConnection, sys: i32, mirror: &str, contents: Option<open::Path>, packages: open::Path) {
    let manpkgs = match get_contents(contents) {
        Err(e) => { error!("Can't read {}: {}", contents.unwrap().path, e); return },
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
            // Use case-insensitive matching, older package archives used lowercase keys
            match str::from_utf8(cap.at(1).unwrap()).unwrap().to_lowercase().as_ref() {
                "package" => pkg.name = Some(val.to_string()),
                "section" => pkg.section = Some(val.to_string()),
                "version" => pkg.version = Some(val.to_string()),
                "architecture" => pkg.arch = Some(val.to_string()),
                "filename" => pkg.filename = Some(val.to_string()),
                _ => {}
            }
        }
    }
    handlepkg(pg, sys, &mirror, &manpkgs, &pkg);
}
