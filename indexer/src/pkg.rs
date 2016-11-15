use std;
use std::io::{Error,ErrorKind,Read};
use postgres;

use open;
use archread;
use man;
use archive::{Format,Archive,ArchiveEntry};

pub struct PkgOpt<'a> {
    pub force: bool,
    pub sys: i32,
    pub cat: &'a str,
    pub pkg: &'a str,
    pub ver: &'a str,
    pub date: &'a str, // TODO: Option to extract date from package metadata itself
    pub arch: Option<&'a str>,
    pub file: open::Path<'a>
}


fn insert_pkg(tr: &postgres::transaction::Transaction, opt: &PkgOpt) -> Option<i32> {
    // The ON CONFLICT .. DO UPDATE is used instead of DO NOTHING because in that case the
    // RETURNING clause wouldn't give us a package id.
    let q = "INSERT INTO packages (system, category, name) VALUES($1, $2, $3)
        ON CONFLICT ON CONSTRAINT packages_system_name_category_key DO UPDATE SET name=$3 RETURNING id";
    let pkgid: i32 = match tr.query(q, &[&opt.sys, &opt.cat, &opt.pkg]) {
        Err(e) => {
            error!("Can't insert package in database: {}", e);
            return None;
        },
        Ok(r) => r.get(0).get(0),
    };

    let q = "SELECT id FROM package_versions WHERE package = $1 AND version = $2";
    let res = tr.query(q, &[&pkgid, &opt.ver]).unwrap();

    let verid : i32;
    if res.is_empty() {
        let q = "INSERT INTO package_versions (package, version, released, arch) VALUES($1, $2, $3::text::date, $4) RETURNING id";
        verid = tr.query(q, &[&pkgid, &opt.ver, &opt.date, &opt.arch]).unwrap().get(0).get(0);
        info!("New package pkgid {} verid {}", pkgid, verid);
        Some(verid)

    } else if opt.force {
        verid = res.get(0).get(0);
        info!("Overwriting package pkgid {} verid {}", pkgid, verid);
        tr.query("DELETE FROM man WHERE package = $1", &[&verid]).unwrap();
        Some(verid)

    } else {
        info!("Package already in database, pkgid {} verid {}", pkgid, res.get(0).get::<usize,i32>(0));
        None
    }
}


fn insert_man_row(tr: &postgres::GenericConnection, verid: i32, path: &str, enc: &str, hash: &[u8]) {
    let (name, sect, locale) = man::parse_path(path).unwrap();
    let locale = if locale == "" { None } else { Some(locale) };
    if let Err(e) = tr.execute(
        "INSERT INTO man (package, name, filename, locale, hash, section, encoding) VALUES ($1, $2, '/'||$3, $4, $5, $6, $7)",
        &[&verid, &name, &path, &locale, &hash, &sect, &enc]
    ) {
        // I think this can only happen if archread gives us the same file twice, which really
        // shouldn't happen. But I'd rather continue with an error logged than panic.
        error!("Can't insert verid {} fn {}: {}", verid, path, e);
    }
}


fn insert_man(tr: &postgres::GenericConnection, verid: i32, paths: &[&str], ent: &mut Read) {
    let (dig, enc, cont) = match man::decode(paths, ent) {
        Err(e) => { error!("Error decoding {}: {}", paths[0], e); return },
        Ok(x) => x,
    };

    // Overwrite entry if the contents are different. It's possible that earlier decoding
    // implementations didn't properly detect the encoding. (On the other hand, due to differences
    // in filenames it's also possible that THIS decoding step went wrong, but that's slightly less
    // likely)
    tr.execute(
        "INSERT INTO contents (hash, content) VALUES($1, $2) ON CONFLICT (hash) DO UPDATE SET content = $2",
        &[&dig.as_ref(), &cont]
    ).unwrap();

    for path in paths {
        insert_man_row(tr, verid, path, enc, dig.as_ref());
        debug!("Inserted man page: {} ({})", path, enc);
    }
}


fn insert_link(tr: &postgres::GenericConnection, verid: i32, src: &str, dest: &str) {
    let res = tr.query("SELECT hash, encoding FROM man WHERE package = $1 AND filename = '/'||$2", &[&verid, &dest]).unwrap();
    if res.is_empty() { /* Can happen if man::decode() failed previously. */
        error!("Link to unindexed man page: {} -> {}", src, dest);
        return;
    }
    let hash: Vec<u8> = res.get(0).get(0);
    let enc: String = res.get(0).get(1);
    insert_man_row(tr, verid, src, &enc, &hash);
    debug!("Inserted man link: {} -> {}", src, dest);
}


fn with_pkg<F,T>(f: open::Path, cb: F) -> std::io::Result<T>
    where F: FnOnce(Option<ArchiveEntry>) -> std::io::Result<T>
{
    let mut rd = f.open()?;
    let ent = match Archive::open_archive(&mut rd)? {
        None => return cb(None),
        Some(x) => x,
    };

    // .deb ("2.0")
    if ent.format() == Format::Ar && ent.path() == Some("debian-binary") {
        let mut ent = ent.next()?;
        while let Some(mut e) = ent {
            if e.path().map(|p| p.starts_with("data.tar")) == Some(true) {
                return cb(Archive::open_archive(&mut e)?);
            }
            ent = e.next()?
        }
        Err(Error::new(ErrorKind::Other, "Debian file without data.tar"))

    // any other archive (Arch/FreeBSD .tar)
    } else {
        cb(Some(ent))
    }
}


fn index_pkg(tr: &postgres::GenericConnection, opt: &PkgOpt, verid: i32) -> std::io::Result<()> {
    let indexfunc = |paths: &[&str], ent: &mut ArchiveEntry| {
        insert_man(tr, verid, paths, ent);
        Ok(()) /* Don't propagate errors, continue handling other man pages */
    };

    let missed = with_pkg(opt.file, |e| { archread::FileList::read(e, man::ismanpath, &indexfunc) })?
        .links(|src, dest| { insert_link(tr, verid, src, dest) });

    if let Some(missed) = missed {
        warn!("Some links were missed, reading package again");
        with_pkg(opt.file, |e| { missed.read(e, indexfunc) })?
    }
    Ok(())
}


pub fn pkg(conn: &postgres::GenericConnection, opt: PkgOpt) {
    info!("Handling pkg: {} / {} / {} - {} @ {} @ {}", opt.sys, opt.cat, opt.pkg, opt.ver, opt.date, opt.file.path);

    let tr = conn.transaction().unwrap();
    tr.set_rollback();

    let verid = match insert_pkg(&tr, &opt) { Some(x) => x, None => return };

    match index_pkg(&tr, &opt, verid) {
        Err(e) => error!("Error reading package: {}", e),
        Ok(_) => tr.set_commit()
    }

    if let Err(e) = tr.finish() {
        error!("Error finishing transaction: {}", e);
    }
}
