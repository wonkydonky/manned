use std::io::Result;
use regex::Regex;
use postgres;

use open;
use pkg;

pub fn sync(pg: &postgres::GenericConnection, sys: i32, cat: &str, mirror: &str) -> Result<()> {
    let pkgs : Vec<String> = open::Path{path: mirror, cache: true, canbelocal: false}
        .dirlist()?.into_iter()
        .filter_map(|(n,d)| if d { None } else { Some(n) })
        .collect();

    lazy_static!(
        // <name>-<version>-<release>.<arch>.rpm
        // As far as I can tell, rpm requires that <version>, <release> and <arch> cannot contain a
        // dash, so this parsing should be reliable.
        static ref RE: Regex = Regex::new(r"^(.+)-([^-]+-[^-]+)\.([^\.-]+)\.rpm$").unwrap();
    );

    for pkg in pkgs {
        let cap = match RE.captures(&pkg) {
            Some(x) => x,
            None => { warn!("Unknown file in directory listing: {}", pkg); continue },
        };
        let (name, ver, arch) = (&cap[1], &cap[2], &cap[3]);

        let path = format!("{}{}", mirror, pkg);
        pkg::pkg(pg, pkg::PkgOpt{
            force: false,
            sys: sys,
            cat: cat,
            pkg: name,
            ver: ver,
            date: pkg::Date::Max,
            arch: Some(arch),
            file: open::Path{
                path: &path,
                cache: false,
                canbelocal: false,
            },
        });
    }
    Ok(())
}
