#!/bin/bash

. ./common.sh


CURL="curl -fSs -A manual-page-crawler,info@manned.org --limit-rate 500k"

TMP=`mktemp -d manned.XXXXXX`

# bash-ism, remove the working directory when we're done.
trap "rm -rf $TMP" EXIT


# Usage: add_pkginfo sysid category name version date
# Returns 0 if the package is already in the database or if an error occured.
# Otherwise adds the package, sets PKGID to the new package_versions.id, and returns 1.
PKGID=
add_pkginfo() {
  RES=`echo "SELECT pv.id FROM packages p JOIN package_versions pv ON pv.package = p.id
        WHERE p.system = :'sysid' AND p.category = :'cat' AND p.name = :'name' AND pv.version = :'ver'"\
    | $PSQL -v "sysid=$1" -v "cat=$2" -v "name=$3" -v "ver=$4"`
  [ "$?" -ne 0 -o -n "$RES" ] && return 0
  RES=`echo "
    INSERT INTO packages (system, category, name) VALUES(:'sysid', :'cat', :'name') ON CONFLICT DO NOTHING;
    INSERT INTO package_versions (version, released, package) VALUES(:'ver', :'rel',
        (SELECT packages.id FROM packages WHERE system = :'sysid' AND category = :'cat' AND name = :'name'))
      RETURNING id"\
    | $PSQL -v "sysid=$1" -v "cat=$2" -v "name=$3" -v "ver=$4" -v "rel=$5"`
  [ "$?" -ne 0 ] && return 0
  PKGID=$RES
  return 1
}


# Usage: add_tar <file> <pkgid> <flags>
# Requires a recent GNU tar for compression autodetect and xz support.
# TODO: tar throws an error if there are no man pages, but this isn't really an
# error.
add_tar() {
  DIR=`mktemp -d "$TMP/tar.XXXXXXX"`
  tar --warning=no-unknown-keyword --warning=no-alone-zero-block -C "$DIR" $3 -xf "$1" --wildcards '*man/*'\
    && ./add_dir.pl "$DIR" "$2"
  RET=$?
  rm -rf "$DIR"
  return $RET
}



add_splittar() { # <url-prefix> <last-sequence> <pkgid> <flags>
  $CURL "$1{"`perl -le "print join ',', 'aa'..'$2'"`'}' | add_tar - $3 $4
}


# Check whether we already have a core file in the DB, otherwise add it.
# (The version we use for the core file is the same as its date)
# If <last-sequence> is set, add_splittar() is used. Otherwise the file is
# assumed to be a regular tar.gz.
check_dist() { # <sysid> <url-prefix> <pkgname> <date> <last-sequence>
  add_pkginfo $1 core "$3" "$4" "$4" && return
  echo "===> $3"
  if [ -n "$5" ]; then
    add_splittar "$2" "$5" $PKGID -z
  else
    COMP=-z
    [ "${2##*.}" = "txz" ] && COMP=-J
    $CURL "$2" | add_tar - $PKGID $COMP
  fi
}


# Adds a FreeBSD 1.0 package. These lack version information and categories and
# are in general not as well organized the package repositories in the later
# versions.
check_oldpkg() { # <sysid> <url> <pkgname> <date>
  add_pkginfo $1 "packages" "$3" "$4" "$4" && return
  echo "===> $3"
  $CURL "$2" | add_tar - $PKGID -z
}


check_pkg() { # <sysid> <base-url> <category> <filename> <name> <version>
  SYSID=$1
  URL=$2
  CAT=$3
  FN=$4
  NAME=$5
  VER=$6
  echo "===> $NAME $VER"
  $CURL "$URL/$CAT/$FN" -o "$TMP/$FN" || return 1

  DATE=`tar -tvf "$TMP/$FN" '+DESC' | perl -lne 's/.+ ([^ ]+) [^ ]+ \+DESC$/print $1/e'`
  if [ -z "$DATE" ]; then
    echo "Error: No date found for +DESC"
    rm -f "$TMP/$FN"
    return
  fi

  add_pkginfo $SYSID $CAT $NAME $VER $DATE
  add_tar "$TMP/$FN" $PKGID
  rm -f "$TMP/$FN"
}


# Will check and index a packages/ directory. Uses the 'Latest/' directory as a
# hint to split the package name from its version, and the other directories
# (except All/) to find the actual packages and their category. Date of the
# packages is extracted from the last modification time of the '+DESC' file in
# each tarball.
# This is for FreeBSD pre-9.3
check_pkgdir() { # <sysid> <url>
  SYSID=$1
  URL=$2
  # Get the list of categories from the lighttpd directory index.
  $CURL "$URL/" | perl -lne 'm{href="([a-z0-9-]+)/">\1</a>/} && print $1' >"$TMP/categories"
  # Get the list of package names without version string.
  $CURL "$URL/Latest/" | perl -lne 'm{href="([^ "]+)(\.t[bg]z)">\1\2</a>} && print $1' >"$TMP/pkgnames"
  if [ \( ! -s "$TMP/categories" \) -o \( ! -s "$TMP/pkgnames" \) ]; then
    echo "== Error fetching package names or directory index."
    rm -f "$TMP/categories" "$TMP/pkgnames"
    return
  fi

  # Now check each category directory
  while read CAT; do
    $CURL "$URL/$CAT/" | perl -lne 'm{href="([^ "]+\.t[bg]z)">\1</a>} && print $1' >"$TMP/pkglist"
    if [ ! -s "$TMP/pkglist" ]; then
      echo "== Error fetching package index for /$CAT/"
      continue
    fi
    perl -l - "$TMP/pkgnames" "$TMP/pkglist" $SYSID $CAT <<'EOP' >"$TMP/newpkgs"
      ($names, $list, $sysid, $cat) = @ARGV;

      use DBI;
      $db = DBI->connect('dbi:Pg:dbname=manned', 'manned', '', {RaiseError => 1});

      open F, '<', $names or die $!;
      %names = map { chomp; ($_,1) } <F>;
      close F;

      open F, '<', $list or die $!;
      while(<F>) {
        chomp;
        warn "Unknown extension for package: $_\n" if !/^(.+)\.(t[bg]z)$/;
        ($c,$n,$e,$v)=($_,$1,$2,'');
        $v = $v ? "$1-$v" : $1 while(!$names{$n} and $n =~ s/-([^-]+)$//);
        if(!$n || !$names{$n} || !$v) {
          warn "== Unknown package: $c\n";
        } else {
          print "$c $n $v" if !$db->selectrow_arrayref(q{
            SELECT 1 FROM packages p JOIN package_versions pv ON pv.package = p.id
              WHERE p.system = ? AND p.category = ? AND p.name = ? AND pv.version = ?}, {}, $sysid, $cat, $n, $v);
        }
      }
      close F;
EOP

    while read NFO; do
      check_pkg $SYSID $URL $CAT $NFO
    done <"$TMP/newpkgs"

    rm -f "$TMP/pkglist" "$TMP/newpkgs"
  done <"$TMP/categories"

  rm -f "$TMP/categories" "$TMP/pkgnames"
}


# For FreeBSD 9.3
check_pkg2() {
  SYSID=$1
  URL=$2
  NAME=$3
  CAT=$4
  # Get the package version and file name from the index.
  # Get the shortest file name, as, e.g. "apq" will also match "apq-mysql-...",
  # this is yet another ugly heuristic...
  REGNAME=`echo "$NAME" | sed 's/[.+]/\\\&/g'`
  FN=`grep -o -E "[^+a-zA-Z0-9_.-]$REGNAME-"'([^ "]+)\.txz' "$TMP/index" | sed 's/^.//' | awk '{print length, $0}' | sort -n | head -n 1 | awk '{print $2}'`
  VER=`echo "$FN" | sed "s/^$REGNAME-//" | sed 's/\.txz$//'`

  echo "===> $NAME $VER"
  $CURL "$URL/All/$FN" -o "$TMP/pkg.txz" || return 1

  # Get the highest last modified time and use that as the package release
  # date. Not super reliable, but for the lack of a simple alternative...
  DATE=`tar -tPvf "$TMP/pkg.txz" | awk '{print $4}' | sort -r |head -n 1`

  add_pkginfo $SYSID $CAT $NAME $VER $DATE
  add_tar "$TMP/pkg.txz" $PKGID
  rm -f "$TMP/pkg.txz"
}


# Fetch packages from the FreeBSD 9.3 package repositories.
check_pkgdir2() {
  SYSID=$1
  URL=$2
  # Get meta-data from all packages
  $CURL "$URL/packagesite.txz" | tar -C "$TMP" -xJf- packagesite.yaml || return 1
  # And get the actual file index, because the metadata is not always correct.
  # (In particular, the version in the metadata may not be the same as the
  # version available in All/, so we use All/ to fetch the version & file name)
  $CURL "$URL/All/" >"$TMP/index"

  # This is NOT a very robust way of reading YAML, but happens to work on all packagesite.yaml's I saw
  perl -lne '($n)=/"name":"([^ "]+)"/; ($c)=m{"origin":"([^ "/]+)/}; print "$n $c"' < "$TMP/packagesite.yaml" >"$TMP/pkglist"

  while read NFO; do
    check_pkg2 $SYSID $URL $NFO
  done <"$TMP/pkglist"

  rm -f "$TMP/packagesite.yaml" "$TMP/pkglist" "$TMP/index"
}


# For FreeBSD 10.0+
check_pkg3() {
  SYSID=$1
  URL=$2
  NAME=$3
  VER=$4
  CAT=$5
  FN=$6

  echo "===> $NAME $VER"
  $CURL "$URL/All/$FN" -o "$TMP/pkg.txz" || return 1

  # Get the highest last modified time and use that as the package release
  # date. Not super reliable, but for the lack of a simple alternative...
  DATE=`tar -tPvf "$TMP/pkg.txz" | awk '{print $4}' | sort -r |head -n 1`

  add_pkginfo $SYSID $CAT $NAME $VER $DATE
  add_tar "$TMP/pkg.txz" $PKGID
  rm -f "$TMP/pkg.txz"
}


# Fetch packages from the FreeBSD 10.0+ package repositories
# (Same as FreeBSD 9.3, but without all the uglyness to guess versions, the packagesite.yaml file is correct this time)
check_pkgdir3() {
  SYSID=$1
  URL=$2
  $CURL "$URL/packagesite.txz" | tar -C "$TMP" -xJf- packagesite.yaml || return 1

  perl -lne '($n)=/"name":"([^ "]+)"/; ($v)=/"version":"([^ "]+)"/; ($c)=m{"origin":"([^ "/]+)}; ($f)=m{"path":"All/([^ "]+)"}; print "$n $v $c $f"' < "$TMP/packagesite.yaml" >"$TMP/pkglist"

  while read NFO; do
    check_pkg3 $SYSID $URL $NFO
  done <"$TMP/pkglist"

  rm -f "$TMP/packagesite.yaml" "$TMP/pkglist"
}


f1_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/1.0-RELEASE"
  echo "============ $MIR"
  # Core distribution
  check_dist 29 "$MIR/tarballs/bindist/bin_tgz." "core-bindist" "1993-11-15" dc
  check_dist 29 "$MIR/tarballs/xfree86/doc.tgz" "core-xfree86-doc" "1993-10-25"
  check_dist 29 "$MIR/tarballs/xfree86/fontserv.tgz" "core-xfree86-fontserv" "1993-10-21"
  check_dist 29 "$MIR/tarballs/xfree86/man.tgz" "core-xfree86-man" "1993-10-20"
  check_dist 29 "$MIR/tarballs/xfree86/pex.tgz" "core-xfree86-pex" "1993-10-21"
  # A few packages
  check_oldpkg 29 "$MIR/packages/emacs-19-19_bin.tgz" "emacs-19-19_bin" "1993-09-13"
  check_oldpkg 29 "$MIR/packages/f2c_bin.tgz" "f2c_bin" "1993-10-01"
  check_oldpkg 29 "$MIR/packages/fileutils_bin.tgz" "fileutils_bin" "1993-10-06"
  check_oldpkg 29 "$MIR/packages/ghostscript_bin.tgz" "ghostscript_bin" "1993-10-02"
  check_oldpkg 29 "$MIR/packages/gopher_bin.tgz" "gopher_bin" "1993-10-15"
  check_oldpkg 29 "$MIR/packages/info-zip_bin.tgz" "info-zip_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/jpeg_bin.tgz" "jpeg_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/kermit_bin.tgz" "kermit_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/ksh_bin.tgz" "ksh_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/miscutils_bin.tgz" "miscutils_bin" "1993-09-06"
  check_oldpkg 29 "$MIR/packages/mtools_bin.tgz" "mtools_bin" "1993-08-30"
  check_oldpkg 29 "$MIR/packages/pbmplus_bin.tgz" "pbmplus_bin" "1993-10-05"
  check_oldpkg 29 "$MIR/packages/pkg_install.tar.gz" "pkg_install" "1993-10-10"
  check_oldpkg 29 "$MIR/packages/shellutils_bin.tgz" "shellutils_bin" "1993-10-06"
  check_oldpkg 29 "$MIR/packages/tcl_bin.tgz" "tcl_bin" "1993-09-18"
  check_oldpkg 29 "$MIR/packages/tcsh_bin.tgz" "tcsh_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/textutils_bin.tgz" "textutils_bin" "1993-09-05"
  check_oldpkg 29 "$MIR/packages/tk_bin.tgz" "tk_bin" "1993-09-18"
  check_oldpkg 29 "$MIR/packages/urt_bin.tgz" "urt_bin" "1993-10-05"
  check_oldpkg 29 "$MIR/packages/xlock_bin.tgz" "xlock_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/xv_bin.tgz" "xv_bin" "1993-09-06"
  check_oldpkg 29 "$MIR/packages/xview32b.tgz" "xview32b" "1993-09-16"
  check_oldpkg 29 "$MIR/packages/zsh_bin.tgz" "zsh_bin" "1993-09-04"
}

f2_0_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.0.5-RELEASE"
  echo "============ $MIR"
  check_dist 30 "$MIR/des/des.aa" "core-des-des" "1995-06-11"
  check_dist 30 "$MIR/des/krb." "core-des-krb" "1995-06-11" ac
  check_dist 30 "$MIR/manpages/manpages." "core-manpages" "1995-06-09" al
}

f2_1_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.1.5-RELEASE"
  echo "============ $MIR"
  check_dist 31 "$MIR/des/des.aa" "core-des-des" "1996-07-16"
  check_dist 31 "$MIR/des/krb." "core-des-krb" "1996-07-16" ac
  check_dist 31 "$MIR/manpages/manpages." "core-manpages" "1996-07-16" am
}

f2_1_7() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.1.7-RELEASE"
  echo "============ $MIR"
  check_dist 32 "$MIR/des/des.aa" "core-des-des" "1997-02-19"
  check_dist 32 "$MIR/des/krb." "core-des-krb" "1997-02-19" ac
  check_dist 32 "$MIR/manpages/manpages." "core-manpages" "1997-02-19" am
}

f2_2_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.2-RELEASE"
  echo "============ $MIR"
  check_dist 33 "$MIR/des/des." "core-des-des" "1997-05-20" ab
  check_dist 33 "$MIR/des/krb." "core-des-krb" "1997-05-20" ac
  check_dist 33 "$MIR/manpages/manpages." "core-manpages" "1997-05-20" ap
}

f2_2_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.5-RELEASE"
  echo "============ $MIR"
  check_dist 34 "$MIR/des/des." "core-des-des" "1997-10-22" ab
  check_dist 34 "$MIR/des/krb." "core-des-krb" "1997-10-22" ad
  check_dist 34 "$MIR/manpages/manpages." "core-manpages" "1997-10-22" an
}

f2_2_6() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.6-RELEASE"
  echo "============ $MIR"
  check_dist 35 "$MIR/des/des." "core-des-des" "1998-03-25" ab
  check_dist 35 "$MIR/des/krb." "core-des-krb" "1998-03-25" ad
  check_dist 35 "$MIR/manpages/manpages." "core-manpages" "1998-03-25" ao
}

f2_2_7() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.7-RELEASE"
  echo "============ $MIR"
  check_dist 36 "$MIR/des/des." "core-des-des" "1998-07-22" ab
  check_dist 36 "$MIR/des/krb." "core-des-krb" "1998-07-22" ad
  check_dist 36 "$MIR/manpages/manpages." "core-manpages" "1998-07-22" ao
  check_dist 36 "$MIR/XF86332/X332fsrv.tgz" "core-XF86332-X332fsrv" "1998-03-01"
  check_dist 36 "$MIR/XF86332/X332man.tgz" "core-XF86332-X332man" "1998-03-01"
  check_dist 36 "$MIR/XF86332/X332set.tgz" "core-XF86332-X332set" "1998-03-01"
}

f2_2_8() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.8-RELEASE"
  echo "============ $MIR"
  check_dist 37 "$MIR/des/des." "core-des-des" "1998-11-29" ab
  check_dist 37 "$MIR/des/krb." "core-des-krb" "1998-11-29" ad
  check_dist 37 "$MIR/manpages/manpages." "core-manpages" "1998-11-29" ax
  check_dist 37 "$MIR/XF86333/Xfsrv.tgz" "core-XF86333-Xfsrv" "1998-11-14"
  check_dist 37 "$MIR/XF86333/Xman.tgz" "core-XF86333-Xman" "1998-11-14"
  check_dist 37 "$MIR/XF86333/Xset.tgz" "core-XF86333-Xset" "1998-11-14"
  check_pkgdir 37 "$MIR/packages"
}

f3_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.0-RELEASE"
  echo "============ $MIR"
  check_dist 38 "$MIR/bin/bin." "core-bin" "1998-10-16" es
  check_dist 38 "$MIR/des/des." "core-des-des" "1998-10-16" ab
  check_dist 38 "$MIR/des/krb." "core-des-krb" "1998-10-16" ae
  check_dist 38 "$MIR/manpages/manpages." "core-manpages" "1998-10-16" bb
  check_dist 38 "$MIR/XF86332/Xfsrv.tgz" "core-XF86332-Xfsrv" "1998-09-28"
  check_dist 38 "$MIR/XF86332/Xman.tgz" "core-XF86332-Xman" "1998-09-28"
  check_dist 38 "$MIR/XF86332/Xset.tgz" "core-XF86332-Xset" "1998-09-28"
}

f3_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.1-RELEASE"
  echo "============ $MIR"
  check_dist 39 "$MIR/bin/bin." "core-bin" "1999-02-15" dx
  check_dist 39 "$MIR/des/des." "core-des-des" "1999-02-15" ab
  check_dist 39 "$MIR/des/krb." "core-des-krb" "1999-02-15" ae
  check_dist 39 "$MIR/manpages/manpages." "core-manpages" "1999-02-15" be
  check_dist 39 "$MIR/XF86332/Xfsrv.tgz" "core-XF86332-Xfsrv" "1998-09-28"
  check_dist 39 "$MIR/XF86332/Xman.tgz" "core-XF86332-Xman" "1998-09-28"
  check_dist 39 "$MIR/XF86332/Xset.tgz" "core-XF86332-Xset" "1998-09-28"
}

f3_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.2-RELEASE"
  echo "============ $MIR"
  check_dist 40 "$MIR/bin/bin." "core-bin" "1999-05-18" eb
  check_dist 40 "$MIR/des/des." "core-des-des" "1999-05-18" ab
  check_dist 40 "$MIR/des/krb." "core-des-krb" "1999-05-18" ae
  check_dist 40 "$MIR/manpages/manpages." "core-manpages" "1999-05-18" be
  check_dist 40 "$MIR/XF86333/Xfsrv.tgz" "core-XF86333-Xfsrv" "1998-11-14"
  check_dist 40 "$MIR/XF86333/Xman.tgz" "core-XF86333-Xman" "1998-11-14"
  check_dist 40 "$MIR/XF86333/Xset.tgz" "core-XF86333-Xset" "1998-11-14"
}

f3_3() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.3-RELEASE"
  echo "============ $MIR"
  check_dist 41 "$MIR/bin/bin." "core-bin" "1999-09-17" ec
  check_dist 41 "$MIR/des/des." "core-des-des" "1999-09-17" ab
  check_dist 41 "$MIR/des/krb." "core-des-krb" "1999-09-17" ae
  check_dist 41 "$MIR/manpages/manpages." "core-manpages" "1999-09-17" au
  check_dist 41 "$MIR/XF86335/Xfsrv.tgz" "core-XF86335-Xfsrv" "1999-08-31"
  check_dist 41 "$MIR/XF86335/Xman.tgz" "core-XF86335-Xman" "1999-08-31"
  check_dist 41 "$MIR/XF86335/Xset.tgz" "core-XF86335-Xset" "1999-08-31"
}

f3_4() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.4-RELEASE"
  echo "============ $MIR"
  check_dist 42 "$MIR/bin/bin." "core-bin" "1999-12-20" ef
  check_dist 42 "$MIR/des/des." "core-des-des" "1999-12-20" ac
  check_dist 42 "$MIR/des/krb." "core-des-krb" "1999-12-20" ae
  check_dist 42 "$MIR/manpages/manpages." "core-manpages" "1999-12-20" av
  check_dist 42 "$MIR/XF86335/Xfsrv.tgz" "core-XF86335-Xfsrv" "1999-08-31"
  check_dist 42 "$MIR/XF86335/Xman.tgz" "core-XF86335-Xman" "1999-08-31"
  check_dist 42 "$MIR/XF86335/Xset.tgz" "core-XF86335-Xset" "1999-08-31"
  check_pkgdir 42 "$MIR/packages"
}

f3_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.5-RELEASE"
  echo "============ $MIR"
  check_dist 43 "$MIR/bin/bin." "core-bin" "2000-06-22" eg
  check_dist 43 "$MIR/des/des." "core-des-des" "2000-06-22" ac
  check_dist 43 "$MIR/des/krb." "core-des-krb" "2000-06-22" ae
  check_dist 43 "$MIR/manpages/manpages." "core-manpages" "2000-06-22" av
  check_dist 43 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2000-01-08"
  check_dist 43 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2000-01-08"
  check_dist 43 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2000-01-08"
  check_pkgdir 43 "$MIR/packages"
}

f3_5_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.5.1-RELEASE"
  echo "============ $MIR"
  check_dist 44 "$MIR/bin/bin." "core-bin" "2000-07-20" eg
  check_dist 44 "$MIR/des/des." "core-des-des" "2000-07-20" ac
  check_dist 44 "$MIR/des/krb." "core-des-krb" "2000-07-20" ae
  check_dist 44 "$MIR/manpages/manpages." "core-manpages" "2000-07-20" av
  check_dist 44 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2000-01-08"
  check_dist 44 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2000-01-08"
  check_dist 44 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2000-01-08"
  check_pkgdir 44 "$MIR/packages"
}

f4_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.0-RELEASE"
  echo "============ $MIR"
  check_dist 45 "$MIR/bin/bin." "core-bin" "2000-03-20" ev
  check_dist 45 "$MIR/crypto/crypto." "core-crypto" "2000-03-20" aj
  check_dist 45 "$MIR/crypto/krb4." "core-crypto-krb4" "2000-03-20" ae
  check_dist 45 "$MIR/crypto/krb5." "core-crypto-krb5" "2000-03-20" ad
  check_dist 45 "$MIR/games/games." "core-games" "2000-03-20" ak
  check_dist 45 "$MIR/manpages/manpages." "core-manpages" "2000-03-20" aw
  check_dist 45 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2001-03-22"
  check_dist 45 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2001-03-22"
  check_dist 45 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2001-03-22"
}

f4_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.1-RELEASE"
  echo "============ $MIR"
  check_dist 46 "$MIR/bin/bin." "core-bin" "2000-07-27" fb
  check_dist 46 "$MIR/crypto/crypto." "core-crypto" "2000-07-27" aj
  check_dist 46 "$MIR/crypto/krb4." "core-crypto-krb4" "2000-07-27" ae
  check_dist 46 "$MIR/crypto/krb5." "core-crypto-krb5" "2000-07-27" ad
  check_dist 46 "$MIR/games/games." "core-games" "2000-07-27" ak
  check_dist 46 "$MIR/manpages/manpages." "core-manpages" "2000-07-27" ax
  check_dist 46 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2000-07-25"
  check_dist 46 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2000-07-25"
  check_dist 46 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2000-07-25"
}

f4_1_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.1.1-RELEASE"
  echo "============ $MIR"
  check_dist 47 "$MIR/bin/bin." "core-bin" "2000-09-25" fc
  check_dist 47 "$MIR/crypto/crypto." "core-crypto" "2000-09-25" ak
  check_dist 47 "$MIR/crypto/krb4." "core-crypto-krb4" "2000-09-25" ae
  check_dist 47 "$MIR/crypto/krb5." "core-crypto-krb5" "2000-09-25" ad
  check_dist 47 "$MIR/games/games." "core-games" "2000-09-25" ak
  check_dist 47 "$MIR/manpages/manpages." "core-manpages" "2000-09-25" ax
  check_dist 47 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2000-07-25"
  check_dist 47 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2000-07-25"
  check_dist 47 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2000-07-25"
  check_pkgdir 47 "$MIR/packages"
}

f4_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.2-RELEASE"
  echo "============ $MIR"
  check_dist 48 "$MIR/bin/bin." "core-bin" "2000-11-21" fc
  check_dist 48 "$MIR/crypto/crypto." "core-crypto" "2000-11-21" al
  check_dist 48 "$MIR/crypto/krb4." "core-crypto-krb4" "2000-11-21" ae
  check_dist 48 "$MIR/crypto/krb5." "core-crypto-krb5" "2000-11-21" ad
  check_dist 48 "$MIR/games/games." "core-games" "2000-11-21" ak
  check_dist 48 "$MIR/manpages/manpages." "core-manpages" "2000-11-21" ax
  check_dist 48 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2000-07-25"
  check_dist 48 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2000-07-25"
  check_dist 48 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2000-07-25"
  check_pkgdir 48 "$MIR/packages"
}

f4_3() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.3-RELEASE"
  echo "============ $MIR"
  check_dist 49 "$MIR/bin/bin." "core-bin" "2001-04-20" fg
  check_dist 49 "$MIR/crypto/crypto." "core-crypto" "2001-04-20" al
  check_dist 49 "$MIR/crypto/krb4." "core-crypto-krb4" "2001-04-20" ae
  check_dist 49 "$MIR/crypto/krb5." "core-crypto-krb5" "2001-04-20" ae
  check_dist 49 "$MIR/games/games." "core-games" "2001-04-20" ak
  check_dist 49 "$MIR/manpages/manpages." "core-manpages" "2001-04-20" ay
  check_dist 49 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2001-03-22"
  check_dist 49 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2001-03-22"
  check_dist 49 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2001-03-22"
  check_pkgdir 49 "$MIR/packages"
}

f4_4() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.4-RELEASE"
  echo "============ $MIR"
  check_dist 50 "$MIR/bin/bin." "core-bin" "2001-09-20" fk
  check_dist 50 "$MIR/crypto/crypto." "core-crypto" "2001-09-20" ak
  check_dist 50 "$MIR/crypto/krb4." "core-crypto-krb4" "2001-09-20" ae
  check_dist 50 "$MIR/crypto/krb5." "core-crypto-krb5" "2001-09-20" ad
  check_dist 50 "$MIR/games/games." "core-games" "2001-09-20" ak
  check_dist 50 "$MIR/manpages/manpages." "core-manpages" "2001-09-20" az
  check_dist 50 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2001-09-05"
  check_dist 50 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2001-09-05"
  check_dist 50 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2001-09-05"
  check_pkgdir 50 "$MIR/packages"
}

f4_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.5-RELEASE"
  echo "============ $MIR"
  check_dist 51 "$MIR/bin/bin." "core-bin" "2002-01-29" fm
  check_dist 51 "$MIR/crypto/crypto." "core-crypto" "2002-01-29" al
  check_dist 51 "$MIR/crypto/krb4." "core-crypto-krb4" "2002-01-29" ae
  check_dist 51 "$MIR/crypto/krb5." "core-crypto-krb5" "2002-01-29" ae
  check_dist 51 "$MIR/games/games." "core-games" "2002-01-29" ak
  check_dist 51 "$MIR/manpages/manpages." "core-manpages" "2002-01-29" az
  check_dist 51 "$MIR/XF86336/Xfsrv.tgz" "core-XF86336-Xfsrv" "2002-01-08"
  check_dist 51 "$MIR/XF86336/Xman.tgz" "core-XF86336-Xman" "2002-01-08"
  check_dist 51 "$MIR/XF86336/Xset.tgz" "core-XF86336-Xset" "2002-01-08"
  check_pkgdir 51 "$MIR/packages"
}

f4_6() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.6-RELEASE"
  echo "============ $MIR"
  check_dist 52 "$MIR/bin/bin." "core-bin" "2002-06-15" fp
  check_dist 52 "$MIR/crypto/crypto." "core-crypto" "2002-06-15" al
  check_dist 52 "$MIR/crypto/krb4." "core-crypto-krb4" "2002-06-15" ae
  check_dist 52 "$MIR/crypto/krb5." "core-crypto-krb5" "2002-06-15" ae
  check_dist 52 "$MIR/games/games." "core-games" "2002-06-15" ak
  check_dist 52 "$MIR/manpages/manpages." "core-manpages" "2002-06-15" az
  check_pkgdir 52 "$MIR/packages"
}

f4_6_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.6.2-RELEASE"
  echo "============ $MIR"
  check_dist 53 "$MIR/bin/bin." "core-bin" "2002-08-15" fq
  check_dist 53 "$MIR/crypto/crypto." "core-crypto" "2002-08-15" am
  check_dist 53 "$MIR/crypto/krb4." "core-crypto-krb4" "2002-08-15" ae
  check_dist 53 "$MIR/crypto/krb5." "core-crypto-krb5" "2002-08-15" ae
  check_dist 53 "$MIR/games/games." "core-games" "2002-08-15" ak
  check_dist 53 "$MIR/manpages/manpages." "core-manpages" "2002-08-15" az
  check_pkgdir 53 "$MIR/packages"
}

f4_7() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.7-RELEASE"
  echo "============ $MIR"
  check_dist 54 "$MIR/bin/bin." "core-bin" "2002-10-10" fr
  check_dist 54 "$MIR/crypto/crypto." "core-crypto" "2002-10-10" an
  check_dist 54 "$MIR/crypto/krb4." "core-crypto-krb4" "2002-10-10" af
  check_dist 54 "$MIR/crypto/krb5." "core-crypto-krb5" "2002-10-10" af
  check_dist 54 "$MIR/games/games." "core-games" "2002-10-10" ak
  check_dist 54 "$MIR/manpages/manpages." "core-manpages" "2002-10-10" bc
  check_pkgdir 54 "$MIR/packages"
}

f4_8() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.8-RELEASE"
  echo "============ $MIR"
  check_dist 55 "$MIR/bin/bin." "core-bin" "2003-04-03" ft
  check_dist 55 "$MIR/crypto/crypto." "core-crypto" "2003-04-03" au
  check_dist 55 "$MIR/crypto/krb4." "core-crypto-krb4" "2003-04-03" ag
  check_dist 55 "$MIR/crypto/krb5." "core-crypto-krb5" "2003-04-03" af
  check_dist 55 "$MIR/games/games." "core-games" "2003-04-03" ak
  check_dist 55 "$MIR/manpages/manpages." "core-manpages" "2003-04-03" bd
  check_pkgdir 55 "$MIR/packages"
}

f4_9() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.9-RELEASE"
  echo "============ $MIR"
  check_dist 56 "$MIR/bin/bin." "core-bin" "2003-10-28" fv
  check_dist 56 "$MIR/crypto/crypto." "core-crypto" "2003-10-28" au
  check_dist 56 "$MIR/crypto/krb4." "core-crypto-krb4" "2003-10-28" ag
  check_dist 56 "$MIR/crypto/krb5." "core-crypto-krb5" "2003-10-28" af
  check_dist 56 "$MIR/games/games." "core-games" "2003-10-28" ak
  check_dist 56 "$MIR/manpages/manpages." "core-manpages" "2003-10-28" bd
  check_pkgdir 56 "$MIR/packages"
}

f4_10() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.10-RELEASE"
  echo "============ $MIR"
  check_dist 57 "$MIR/bin/bin." "core-bin" "2004-05-27" fw
  check_dist 57 "$MIR/crypto/crypto." "core-crypto" "2004-05-27" au
  check_dist 57 "$MIR/crypto/krb4." "core-crypto-krb4" "2004-05-27" ag
  check_dist 57 "$MIR/crypto/krb5." "core-crypto-krb5" "2004-05-27" af
  check_dist 57 "$MIR/games/games." "core-games" "2004-05-27" ak
  check_dist 57 "$MIR/manpages/manpages." "core-manpages" "2004-05-27" bd
  check_pkgdir 57 "$MIR/packages"
}

f4_11() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/4.11-RELEASE"
  echo "============ $MIR"
  check_dist 58 "$MIR/bin/bin." "core-bin" "2005-01-25" fx
  check_dist 58 "$MIR/crypto/crypto." "core-crypto" "2005-01-25" au
  check_dist 58 "$MIR/crypto/krb4." "core-crypto-krb4" "2005-01-25" ag
  check_dist 58 "$MIR/crypto/krb5." "core-crypto-krb5" "2005-01-25" af
  check_dist 58 "$MIR/games/games." "core-games" "2005-01-25" ak
  check_dist 58 "$MIR/manpages/manpages." "core-manpages" "2005-01-25" be
  check_pkgdir 58 "$MIR/packages"
}

f5_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/5.0-RELEASE"
  echo "============ $MIR"
  check_dist 59 "$MIR/crypto/crypto." "core-crypto" "2003-01-14" an
  check_dist 59 "$MIR/crypto/krb4." "core-crypto-krb4" "2003-01-14" af
  check_dist 59 "$MIR/crypto/krb5." "core-crypto-krb5" "2003-01-14" ag
  check_dist 59 "$MIR/games/games." "core-games" "2003-01-14" ag
  check_dist 59 "$MIR/manpages/manpages." "core-manpages" "2003-01-14" ay
  check_pkgdir 59 "$MIR/packages"
}

f5_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/5.1-RELEASE"
  echo "============ $MIR"
  check_dist 60 "$MIR/crypto/crypto." "core-crypto" "2003-06-09" ae
  check_dist 60 "$MIR/crypto/krb5.aa" "core-crypto-krb5" "2003-06-09"
  check_dist 60 "$MIR/games/games." "core-games" "2003-06-09" ab
  check_dist 60 "$MIR/manpages/manpages." "core-manpages" "2003-06-09" ae
  check_pkgdir 60 "$MIR/packages"
}

f5_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/5.2-RELEASE"
  echo "============ $MIR"
  check_dist 61 "$MIR/crypto/crypto." "core-crypto" "2004-01-09" ae
  check_dist 61 "$MIR/crypto/krb5.aa" "core-crypto-krb5" "2004-01-09"
  check_dist 61 "$MIR/games/games." "core-games" "2004-01-09" ab
  check_dist 61 "$MIR/manpages/manpages." "core-manpages" "2004-01-09" ae
  check_pkgdir 61 "$MIR/packages"
}

f5_2_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/5.2.1-RELEASE"
  echo "============ $MIR"
  check_dist 62 "$MIR/crypto/crypto." "core-crypto" "2004-02-25" ae
  check_dist 62 "$MIR/crypto/krb5.aa" "core-crypto-krb5" "2004-02-25"
  check_dist 62 "$MIR/games/games." "core-games" "2004-02-25" ab
  check_dist 62 "$MIR/manpages/manpages." "core-manpages" "2004-02-25" ae
  check_pkgdir 62 "$MIR/packages"
}

f5_3() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/5.3-RELEASE"
  echo "============ $MIR"
  check_dist 63 "$MIR/base/base." "core-base" "2004-11-06" bg
  check_dist 63 "$MIR/games/games." "core-games" "2004-11-06" ab
  check_dist 63 "$MIR/manpages/manpages." "core-manpages" "2004-11-06" ae
  check_pkgdir 63 "$MIR/packages"
}

f5_4() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/5.4-RELEASE"
  echo "============ $MIR"
  check_dist 64 "$MIR/base/base." "core-base" "2005-05-09" bg
  check_dist 64 "$MIR/games/games." "core-games" "2005-05-09" ab
  check_dist 64 "$MIR/manpages/manpages." "core-manpages" "2005-05-09" ae
  check_pkgdir 64 "$MIR/packages"
}

f5_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/5.5-RELEASE"
  echo "============ $MIR"
  check_dist 65 "$MIR/base/base." "core-base" "2006-05-25" bg
  check_dist 65 "$MIR/games/games." "core-games" "2006-05-25" ab
  check_dist 65 "$MIR/manpages/manpages." "core-manpages" "2006-05-25" ae
  check_pkgdir 65 "$MIR/packages"
}

f6_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/6.0-RELEASE"
  echo "============ $MIR"
  check_dist 66 "$MIR/base/base." "core-base" "2005-11-04" bp
  check_dist 66 "$MIR/games/games." "core-games" "2005-11-04" ab
  check_dist 66 "$MIR/manpages/manpages." "core-manpages" "2005-11-04" af
  check_pkgdir 66 "$MIR/packages"
}

f6_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/6.1-RELEASE"
  echo "============ $MIR"
  check_dist 67 "$MIR/base/base." "core-base" "2006-05-08" bd
  check_dist 67 "$MIR/games/games." "core-games" "2006-05-08" ab
  check_dist 67 "$MIR/manpages/manpages." "core-manpages" "2006-05-08" af
  check_pkgdir 67 "$MIR/packages"
}

f6_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/6.2-RELEASE"
  echo "============ $MIR"
  check_dist 68 "$MIR/base/base." "core-base" "2007-01-15" bd
  check_dist 68 "$MIR/games/games." "core-games" "2007-01-15" ab
  check_dist 68 "$MIR/manpages/manpages." "core-manpages" "2007-01-15" af
  check_pkgdir 68 "$MIR/packages"
}

f6_3() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/6.3-RELEASE"
  echo "============ $MIR"
  check_dist 69 "$MIR/base/base." "core-base" "2008-01-18" be
  check_dist 69 "$MIR/games/games." "core-games" "2008-01-18" ab
  check_dist 69 "$MIR/manpages/manpages." "core-manpages" "2008-01-18" af
  check_pkgdir 69 "$MIR/packages"
}

f6_4() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/6.4-RELEASE"
  echo "============ $MIR"
  check_dist 70 "$MIR/base/base." "core-base" "2008-11-28" be
  check_dist 70 "$MIR/games/games." "core-games" "2008-11-28" ab
  check_dist 70 "$MIR/manpages/manpages." "core-manpages" "2008-11-28" af
  check_pkgdir 70 "$MIR/packages"
}

f7_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/7.0-RELEASE"
  echo "============ $MIR"
  check_dist 71 "$MIR/base/base." "core-base" "2008-02-27" bh
  check_dist 71 "$MIR/games/games." "core-games" "2008-02-27" ab
  check_dist 71 "$MIR/manpages/manpages." "core-manpages" "2008-02-27" af
  check_pkgdir 71 "$MIR/packages"
}

f7_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/7.1-RELEASE"
  echo "============ $MIR"
  check_dist 72 "$MIR/base/base." "core-base" "2009-01-04" bi
  check_dist 72 "$MIR/games/games." "core-games" "2009-01-04" ab
  check_dist 72 "$MIR/manpages/manpages." "core-manpages" "2009-01-04" af
  check_pkgdir 72 "$MIR/packages"
}

f7_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/7.2-RELEASE"
  echo "============ $MIR"
  check_dist 73 "$MIR/base/base." "core-base" "2009-05-04" bi
  check_dist 73 "$MIR/games/games." "core-games" "2009-05-04" ab
  check_dist 73 "$MIR/manpages/manpages." "core-manpages" "2009-05-04" af
  check_pkgdir 73 "$MIR/packages"
}

f7_3() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/7.3-RELEASE"
  echo "============ $MIR"
  check_dist 74 "$MIR/base/base." "core-base" "2010-03-23" bi
  check_dist 74 "$MIR/games/games." "core-games" "2010-03-23" ab
  check_dist 74 "$MIR/manpages/manpages." "core-manpages" "2010-03-23" af
  check_pkgdir 74 "$MIR/packages"
}

f7_4() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/7.4-RELEASE"
  echo "============ $MIR"
  check_dist 75 "$MIR/base/base." "core-base" "2011-02-24" bi
  check_dist 75 "$MIR/games/games." "core-games" "2011-02-24" ab
  check_dist 75 "$MIR/manpages/manpages." "core-manpages" "2011-02-24" af
  check_pkgdir 75 "$MIR/packages"
}

f8_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/8.0-RELEASE"
  echo "============ $MIR"
  check_dist 76 "$MIR/base/base." "core-base" "2009-11-25" bl
  check_dist 76 "$MIR/games/games." "core-games" "2009-11-25" ab
  check_dist 76 "$MIR/manpages/manpages." "core-manpages" "2009-11-25" af
  check_pkgdir 76 "$MIR/packages"
}

f8_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/8.1-RELEASE"
  echo "============ $MIR"
  check_dist 77 "$MIR/base/base." "core-base" "2010-07-23" bl
  check_dist 77 "$MIR/games/games." "core-games" "2010-07-23" ab
  check_dist 77 "$MIR/manpages/manpages." "core-manpages" "2010-07-23" ag
  check_pkgdir 77 "$MIR/packages"
}

f8_2() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/8.2-RELEASE/"
  echo "============ $MIR"
  check_dist 78 "$MIR/base/base." "core-base" "2011-02-24" bm
  check_dist 78 "$MIR/games/games." "core-games" "2011-02-24" ab
  check_dist 78 "$MIR/manpages/manpages." "core-manpages" "2011-02-24" ag
  check_pkgdir 78 "$MIR/packages"
}

f8_3() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/8.3-RELEASE/"
  echo "============ $MIR"
  check_dist 79 "$MIR/base/base." "core-base" "2012-04-18" bm
  check_dist 79 "$MIR/games/games." "core-games" "2012-04-18" ab
  check_dist 79 "$MIR/manpages/manpages." "core-manpages" "2012-04-18" ag
  check_pkgdir 79 "$MIR/packages"
}

f8_4() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/8.4-RELEASE/"
  echo "============ $MIR"
  check_dist 84 "$MIR/base/base." "core-base" "2013-06-07" bq
  check_dist 84 "$MIR/games/games." "core-games" "2013-06-07" ab
  check_dist 84 "$MIR/manpages/manpages." "core-manpages" "2013-06-07" ag
  check_pkgdir 84 "$MIR/packages"
}

f9_0() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/9.0-RELEASE/"
  echo "============ $MIR"
  check_dist 80 "$MIR/base.txz" "core-base" "2012-01-12"
  check_dist 80 "$MIR/games.txz" "core-games" "2012-01-12"
  check_pkgdir 80 "$MIR/packages"
}

f9_1() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/9.1-RELEASE/"
  echo "============ $MIR"
  check_dist 85 "$MIR/base.txz" "core-base" "2012-12-30"
  check_dist 85 "$MIR/games.txz" "core-games" "2012-12-30"
  check_pkgdir 85 "$MIR/packages"
}

f9_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/9.2-RELEASE/"
  echo "============ $MIR"
  check_dist 86 "$MIR/base.txz" "core-base" "2013-09-27"
  check_dist 86 "$MIR/games.txz" "core-games" "2013-09-27"
  check_pkgdir 86 "$MIR/packages"
}

f9_3() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/9.3-RELEASE/"
  PKG="http://pkg.freebsd.org/freebsd:9:x86:32/release_3/"
  echo "============ $MIR"
  check_dist 94 "$MIR/base.txz" "core-base" "2014-07-20"
  check_dist 94 "$MIR/games.txz" "core-games" "2014-07-20"
  check_pkgdir2 94 "$PKG"
}

f10_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/10.0-RELEASE/"
  PKG="http://pkg.freebsd.org/freebsd:10:x86:32/release_0/"
  echo "============ $MIR"
  check_dist 95 "$MIR/base.txz" "core-base" "2014-01-20"
  check_dist 95 "$MIR/games.txz" "core-games" "2014-01-20"
  check_pkgdir3 95 "$PKG"
}

f10_1() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/10.1-RELEASE/"
  PKG="http://pkg.freebsd.org/freebsd:10:x86:32/release_1/"
  echo "============ $MIR"
  check_dist 96 "$MIR/base.txz" "core-base" "2014-11-14"
  check_dist 96 "$MIR/games.txz" "core-games" "2014-11-14"
  check_pkgdir3 96 "$PKG"
}

f10_2() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/10.2-RELEASE/"
  PKG="http://pkg.freebsd.org/freebsd:10:x86:32/release_2/"
  echo "============ $MIR"
  check_dist 97 "$MIR/base.txz" "core-base" "2015-08-13"
  check_dist 97 "$MIR/games.txz" "core-games" "2015-08-13"
  check_pkgdir3 97 "$PKG"
}

f10_3() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/10.3-RELEASE/"
  PKG="http://pkg.freebsd.org/freebsd:10:x86:32/release_3/"
  echo "============ $MIR"
  check_dist 98 "$MIR/base.txz" "core-base" "2016-04-04"
  check_dist 98 "$MIR/games.txz" "core-games" "2016-04-04"
  check_pkgdir3 98 "$PKG"
}

f11_0() {
  MIR="http://ftp.dk.freebsd.org/pub/FreeBSD/releases/i386/11.0-RELEASE/"
  PKG="http://pkg.freebsd.org/freebsd:11:x86:32/release_0/"
  echo "============ $MIR"
  check_dist 99 "$MIR/base.txz" "core-base" "2016-10-10"
  check_pkgdir3 99 "$PKG"
}


old() {
  f1_0
  f2_0_5
  f2_1_5
  f2_1_7
  f2_2_2
  f2_2_5
  f2_2_6
  f2_2_7
  f2_2_8
  f3_0
  f3_1
  f3_2
  f3_3
  f3_4
  f3_5
  f3_5_1
  f4_0
  f4_1
  f4_1_1
  f4_2
  f4_3
  f4_4
  f4_5
  f4_6
  f4_6_2
  f4_7
  f4_8
  f4_9
  f4_10
  f4_11
  f5_0
  f5_1
  f5_2
  f5_2_1
  f5_3
  f5_4
  f5_5
  f6_0
  f6_1
  f6_2
  f6_3
  f6_4
  f7_0
  f7_1
  f7_2
  f7_3
  f7_4
  f8_0
  f8_1
  f8_2
  f8_3
  f8_4
  f9_0
  f9_1
  f9_2
  f9_3
  f10_0
  f10_1
  f10_2
  f10_3
  f11_0
}

"$@"
