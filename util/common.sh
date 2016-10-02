#!/bin/bash

CURL="curl -fSs -A manual-page-crawler,info@manned.org --limit-rate 500k"
PSQL="psql -U manned -Awtq"

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

