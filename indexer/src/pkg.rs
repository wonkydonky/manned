use std;
use std::io::Read;
use postgres;

use archive;
use archread;
use man;
use archive::Archive;

pub struct PkgOpt<'a> {
    pub sys: i32,
    pub cat: &'a str,
    pub pkg: &'a str,
    pub ver: &'a str,
    pub date: &'a str,
    pub file: &'a str
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

    // TODO: option to overwrite an existing package version
    let q = "INSERT INTO package_versions (package, version, released) VALUES($1, $2, $3::text::date) RETURNING id";
    let verid: i32 = match tr.query(q, &[&pkgid, &opt.ver, &opt.date]) {
        Err(e) => {
            error!("Can't insert package version in database: {}", e);
            return None;
        },
        Ok(r) => r.get(0).get(0),
    };
    trace!("Package pkgid {} verid {}", pkgid, verid);
    Some(verid)
}


fn insert_man_row(tr: &postgres::GenericConnection, verid: i32, path: &str, hash: &[u8]) {
    // TODO: Store 'encoding' in the database
    let (name, sect, locale) = man::parse_path(path).unwrap();
    if let Err(e) = tr.execute(
        "INSERT INTO man (package, name, filename, locale, hash, section) VALUES ($1, $2, '/'||$3, $4, $5, $6)",
        &[&verid, &name, &path, &locale, &hash, &sect]
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

    // TODO: Overwrite entry if the contents are different? It's possible that earlier decoding
    // implementations didn't properly detect the encoding. (On the other hand, due to differences
    // in filenames it's also possible that THIS decoding step went wrong. Ugh)
    tr.execute(
        "INSERT INTO contents (hash, content) VALUES($1, $2) ON CONFLICT (hash) DO NOTHING",
        &[&dig.as_ref(), &cont]
    ).unwrap();

    for path in paths {
        insert_man_row(tr, verid, path, dig.as_ref());
        debug!("Inserted man page: {} ({})", path, enc);
    }
}


fn insert_link(tr: &postgres::GenericConnection, verid: i32, src: &str, dest: &str) {
    let hash = tr.query("SELECT hash FROM man WHERE package = $1 AND filename = '/'||$2", &[&verid, &dest]).unwrap();
    if hash.is_empty() { /* Can happen if man::decode() failed previously. */
        error!("Link to unindexed man page: {} -> {}", src, dest);
        return;
    }
    let hash: Vec<u8> = hash.get(0).get(0);
    insert_man_row(tr, verid, src, &hash);
    debug!("Inserted man link: {} -> {}", src, dest);
}


fn with_pkg<T,F>(file: &str, cb: F) -> std::io::Result<T>
    where F: FnOnce(Option<archive::ArchiveEntry>) -> std::io::Result<T>
{
    // TODO: Support streaming from URLs
    // TODO: How does .deb support fit into this? (Or anything else with metadata)
    let mut f = try!(std::fs::File::open(file));
    let ent = try!(Archive::open_archive(&mut f));
    cb(ent)
}


fn index_pkg(tr: &postgres::GenericConnection, opt: &PkgOpt, verid: i32) -> std::io::Result<()> {
    let indexfunc = |paths: &[&str], ent: &mut archive::ArchiveEntry| {
        insert_man(tr, verid, paths, ent);
        Ok(()) /* Don't propagate errors, continue handling other man pages */
    };

    let missed = try!(
        with_pkg(opt.file, |ent| { archread::FileList::read(ent, man::ismanpath, &indexfunc) })
    ).links(|src, dest| { insert_link(tr, verid, src, dest) });

    if let Some(missed) = missed {
        warn!("Some links were missed, reading package again");
        try!(with_pkg(opt.file, |ent| { missed.read(ent, indexfunc) }))
    }
    Ok(())
}


pub fn pkg(conn: &postgres::GenericConnection, opt: PkgOpt) {
    info!("Handling pkg: {} / {} / {} - {} @ {} in {}", opt.sys, opt.cat, opt.pkg, opt.ver, opt.date, opt.file);

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
