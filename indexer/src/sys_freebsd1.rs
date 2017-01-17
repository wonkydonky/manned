use std::collections::HashSet;
use std::ascii::AsciiExt;
use std::io::Result;
use regex::Regex;
use postgres;

use open;
use pkg;


// Sync a FreeBSD <= 9.2 package respository.
//
// Reads "." to get a list of categories, "Latest" to get a list of all packages, and all category
// directories to figure out which package belongs in which category.
//
// Splitting a package filename into a package name and version is a hard problem. There are two
// strategies:
// 1. Use the listing from 'Latest' to get the list of package names, and use that to find the
//    longest matching substring in the package filename to split off the version.
// 2. Guessing, like splitver() below.
//
// Both strategies lead to errors. (1) doesn't always work because the 'Latest' directory tends to
// miss a few packages. (2) doesn't always work because version strings are too damn irregular.
// This function tries (1) first, then falls back to (2) if it couldn't find a matching package.
// This combined solution also isn't perfect, as sometimes a package prefix does exist, but is
// incomplete. E.g. 'pear-PHPUnit-1.3.3.tbz' is parsed as 'pear version PHPUnit-1.3.3' rather than
// 'pear-PHPUnit version 1.3.3', because there is a 'pear' package in 'Latest' but no
// 'pear-PHPUnit'. This is handled with a static list of package names to add to the 'pkgs' list,
// see EXTRA_PKGS below.
pub fn sync(pg: &postgres::GenericConnection, sys: i32, arch: &str, mirror: &str) -> Result<()> {
    let path = format!("{}Latest/", mirror);
    let mut pkgs : Vec<String> = open::Path{path: &path, cache: true, canbelocal: false}
        .dirlist()?.into_iter()
        .map(|(n,_)| trimext(&n).to_string())
        .collect();

    pkgs.extend(EXTRA_PKGS.into_iter().map(|e| e.to_string()));
    pkgs.sort_by(|a, b| b.len().cmp(&a.len())); // Longest first

    // List of packages (name+version) we've already seen; Some packages are present in multiple
    // categories, we only index the first found.
    let mut seenpkgs = HashSet::new();

    let cats = open::Path{path: mirror, cache: true, canbelocal: false}
        .dirlist()?.into_iter()
        .filter(|&(ref n,i)| i && n != "All" && n != "Latest")
        .map(|(n,_)| n);

    for cat in cats {
        trace!("Category: {}", cat);
        let path = format!("{}{}/", mirror, cat);
        let lst = open::Path{path: &path, cache: true, canbelocal: false}.dirlist()?.into_iter().map(|(n,_)| n);
        for f in lst {
            let name = trimext(&f);
            if !name.is_ascii() {
                warn!("Non-ASCII package name: {}", f);
                continue;
            }

            // The take() mystifies me; why is it necessary?
            let pkg = pkgs.iter()
                .find(|p| name.len() > p.len()+1 && name.starts_with(&p as &str) && &name[p.len() .. p.len()+1] == "-")
                .take().map(|p| (p as &str, &name[p.len()+1 .. ]))
                .or_else(|| splitver(name));

            if let Some((pkg, ver)) = pkg {
                if !seenpkgs.insert((pkg.to_string(), ver.to_string())) {
                    continue;
                }

                let path = format!("{}{}/{}", mirror, cat, f);
                pkg::pkg(pg, pkg::PkgOpt{
                    force: false,
                    sys: sys,
                    cat: &cat,
                    pkg: pkg,
                    ver: ver,
                    date: pkg::Date::Desc,
                    arch: Some(arch),
                    file: open::Path{
                        path: &path,
                        cache: false,
                        canbelocal: false,
                    },
                });
            } else {
                warn!("Unknown package: {}/{}", cat, f);
            }
        }
    }
    Ok(())
}


fn trimext(n: &str) -> &str {
    n.trim_right_matches(".tgz").trim_right_matches(".tbz")
}


fn splitver(n: &str) -> Option<(&str, &str)> {
    lazy_static!(
        static ref RE1: Regex = Regex::new("^(.+?)-([0-9].*)$").unwrap();
        static ref RE2: Regex = Regex::new("^(.+)-([^-]+)$").unwrap();
    );
    if let Some(cap) = RE1.captures(n) {
        Some((cap.get(1).unwrap().as_str(), cap.get(2).unwrap().as_str()))
    } else if let Some(cap) = RE2.captures(n) {
        Some((cap.get(1).unwrap().as_str(), cap.get(2).unwrap().as_str()))
    } else {
        None
    }
}


// This list may not be complete, and these packages may not necessarily have man pages.
const EXTRA_PKGS : &'static [&'static str] = &[
    "amanda-client",
    "amanda-server",
    "apache-event",
    "apache-itk",
    "apache-peruser",
    "apache-tomcat",
    "apache-worker",
    "bison-devel",
    "boxbackup-devel",
    "boxbackup-devel",
    "ffmpeg-devel",
    "flex-sdk",
    "fpc-gdb",
    "freeradius-mysql",
    "gdb-insight",
    "glib-reference",
    "gmime-24",
    "gmime-24-sharp",
    "gtk-reference",
    "gtk-sharp",
    "gtkmm-reference",
    "horde-content",
    "horde-groupware",
    "horde-timeobjects",
    "horde-webmail",
    "hping-devel",
    "ja-jvim-direct_canna",
    "ja-mutt-devel",
    "kdelibs-experimental",
    "kdepim-runtime",
    "lame-devel",
    "libdivxdecore-devel",
    "libquicktime-lame",
    "libtorrent-rasterbar",
    "linux-netscape-communicator",
    "mkisofs-devel",
    "mldonkey-core-devel",
    "mldonkey-gui-devel",
    "mod_log_sql-dtc",
    "nethack-qt",
    "nfdump-devel",
    "openssl-beta",
    "pear-PHPUnit",
    "pear-XML_Query2XML",
    "pear-phpunit-PHPUnit",
    "pgadmin3-unicode",
    "proftpd-mod_ldap",
    "proftpd-mod_sql_mysql",
    "proftpd-mod_sql_odbc",
    "proftpd-mod_sql_postgres",
    "proftpd-mod_sql_sqlite",
    "proftpd-mod_sql_tds",
    "qt-static",
    "rsyslog-gnutls",
    "rsyslog-gssapi",
    "rsyslog-libdbi",
    "rsyslog-mysql",
    "rsyslog-pgsql",
    "rsyslog-relp",
    "rsyslog-rfc3195",
    "rsyslog-snmp",
    "samba-libsmbclient",
    "samba-nmblookup",
    "squirrelmail-shared_calendars-plugin",
    "tcl-thread",
    "wxgtk2-common-devel",
    "wxgtk2-contrib-common-devel",
    "wxgtk2-utils-devel",
];

