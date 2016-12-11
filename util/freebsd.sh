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
  f9_3
  f10_0
  f10_1
  f10_2
  f10_3
  f11_0
}

"$@"
