
CURL="curl -fSs -A manual-page-crawler,info@manned.org --limit-rate 500k"
PSQL="psql -U manned -Awtq"

TMP=`mktemp -d manned.XXXXXX`

# bash-ism, remove the working directory when we're done.
trap "rm -rf $TMP" EXIT



# Usage: add_tar <file> <pkgid> <flags>
# Requires a recent GNU tar for compression autodetect and xz support.
# TODO: tar throws an error if there are no man pages, but this isn't really an
# error.
add_tar() {
  DIR=`mktemp -d "$TMP/tar.XXXXXXX"`
  tar --warning=no-unknown-keyword -C "$DIR" $3 -xf "$1" --wildcards '*/man/*'\
    && ./add_dir.pl "$DIR" "$2"
  RET=$?
  rm -rf "$DIR"
  return $RET
}

