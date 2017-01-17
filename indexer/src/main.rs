#[macro_use] extern crate log;
#[macro_use] extern crate lazy_static;
#[macro_use] extern crate clap;
extern crate env_logger;
extern crate regex;
extern crate libarchive3_sys;
extern crate libc;
extern crate ring;
extern crate encoding;
extern crate postgres;
extern crate hyper;
extern crate url;
extern crate chrono;

mod archive;
mod archread;
mod man;
mod open;
mod pkg;
mod sys_arch;
mod sys_deb;
mod sys_freebsd1;
mod sys_freebsd2;
mod sys_rpmdir;


// Convenience function to get a system id by short-name. Panics if the system doesn't exist.
fn sysbyshort(conn: &postgres::GenericConnection, short: &str) -> i32 {
    let r = conn.query("SELECT id FROM systems WHERE short = $1", &[&short]).unwrap();
    if r.is_empty() {
        panic!("Invalid system: {}", short);
    }
    r.get(0).get(0)
}


fn main() {
    let arg = clap_app!(indexer =>
        (about: "Manned.org man page indexer")
        (@arg v: -v +multiple "Increase verbosity")
        (@arg dry: --dryrun "Don't actually download and index packages")
        (@subcommand pkg =>
            (about: "Index a single package")
            (@arg force: --force "Overwrite existing indexed package")
            (@arg sys: --sys +required +takes_value "System short-name")
            (@arg cat: --cat +required +takes_value "Package category")
            (@arg pkg: --pkg +required +takes_value "Package name")
            (@arg ver: --ver +required +takes_value "Package version")
            (@arg date: --date +required +takes_value "Package release date")
            (@arg arch: --arch +takes_value "Architecture")
            (@arg FILE: +required "Package file")
        )
        (@subcommand arch =>
            (about: "Index an Arch Linux repository")
            (@arg sys: --sys +required +takes_value "System short-name")
            (@arg mirror: --mirror +required +takes_value "Mirror URL")
            (@arg repo: --repo +required +takes_value "Repository name")
        )
        (@subcommand deb =>
            (about: "Index a Debian repository")
            (@arg sys: --sys +required +takes_value "System short-name")
            (@arg mirror: --mirror +required +takes_value "Mirror URL")
            (@arg contents: --contents +takes_value "Contents file")
            (@arg packages: --packages +required +takes_value "Packages file")
        )
        (@subcommand freebsd1 =>
            (about: "Index packages from a FreeBSD <= 9.2 package repo")
            (@arg sys: --sys +required +takes_value "System short-name")
            (@arg mirror: --mirror +required +takes_value "Mirror URL (should point to the packages/ dir)")
            (@arg arch: --arch +required +takes_value "Arch")
        )
        (@subcommand freebsd2 =>
            (about: "Index packages from a FreeBSD >= 9.3 package repo")
            (@arg sys: --sys +required +takes_value "System short-name")
            (@arg mirror: --mirror +required +takes_value "Mirror URL")
        )
        (@subcommand rpmdir =>
            (about: "Index a bare RPM directory")
            (@arg sys: --sys +required +takes_value "System short-name")
            (@arg cat: --cat +required +takes_value "Category to set for all packages")
            (@arg mirror: --mirror +required +takes_value "Mirror URL")
        )
    ).get_matches();

    unsafe { pkg::DRY_RUN = arg.is_present("dry") };

    let verbose = arg.occurrences_of("v");
    env_logger::LogBuilder::new()
        .filter(Some("indexer"), match verbose {
            0 => log::LogLevelFilter::Warn,
            1 => log::LogLevelFilter::Info,
            2 => log::LogLevelFilter::Debug,
            _ => log::LogLevelFilter::Trace,
        })
        .filter(Some("postgres"), if verbose >= 4 { log::LogLevelFilter::Trace } else { log::LogLevelFilter::Info })
        .init().unwrap();

    if let Err(e) = open::clear_cache() {
        error!("Error clearing cache: {}", e);
        return;
    }

    let dbhost = match std::env::var("MANNED_PG") {
        Ok(x) => x,
        Err(_) => { error!("MANNED_PG not set."); return }
    };
    let db = match postgres::Connection::connect(&dbhost[..], postgres::TlsMode::None) {
        Ok(x) => x,
        Err(x) => { error!("Can't connect to postgres: {}", x); return },
    };
    trace!("Connected to database");

    if let Some(matches) = arg.subcommand_matches("pkg") {
        let date = match matches.value_of("date").unwrap() {
            "deb" => pkg::Date::Deb,
            "desc" => pkg::Date::Desc,
            "max" => pkg::Date::Max,
            s => pkg::Date::Known(s),
        };
        pkg::pkg(&db, pkg::PkgOpt {
            force: matches.is_present("force"),
            sys: sysbyshort(&db, matches.value_of("sys").unwrap()),
            cat: matches.value_of("cat").unwrap(),
            pkg: matches.value_of("pkg").unwrap(),
            ver: matches.value_of("ver").unwrap(),
            date: date,
            arch: matches.value_of("arch"),
            file: open::Path{ path: matches.value_of("FILE").unwrap(), cache: false, canbelocal: true},
        });
    }

    if let Some(matches) = arg.subcommand_matches("arch") {
        sys_arch::sync(&db,
            sysbyshort(&db, matches.value_of("sys").unwrap()),
            matches.value_of("mirror").unwrap(),
            matches.value_of("repo").unwrap()
        );
    }

    if let Some(matches) = arg.subcommand_matches("deb") {
        sys_deb::sync(&db,
            sysbyshort(&db, matches.value_of("sys").unwrap()),
            matches.value_of("mirror").unwrap(),
            matches.value_of("contents").map(|e| { open::Path{ path: e, cache: true, canbelocal: true} }),
            open::Path{ path: matches.value_of("packages").unwrap(), cache: true, canbelocal: true},
        );
    }

    if let Some(matches) = arg.subcommand_matches("freebsd1") {
        sys_freebsd1::sync(&db,
            sysbyshort(&db, matches.value_of("sys").unwrap()),
            matches.value_of("arch").unwrap(),
            matches.value_of("mirror").unwrap()
        ).unwrap_or_else(|e| error!("{}", e));
    }

    if let Some(matches) = arg.subcommand_matches("freebsd2") {
        sys_freebsd2::sync(&db,
            sysbyshort(&db, matches.value_of("sys").unwrap()),
            matches.value_of("mirror").unwrap()
        ).unwrap_or_else(|e| error!("{}", e));
    }

    if let Some(matches) = arg.subcommand_matches("rpmdir") {
        sys_rpmdir::sync(&db,
            sysbyshort(&db, matches.value_of("sys").unwrap()),
            matches.value_of("cat").unwrap(),
            matches.value_of("mirror").unwrap()
        ).unwrap_or_else(|e| error!("{}", e));
    }

    trace!("Exiting");
}
