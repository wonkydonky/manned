#!/bin/sh

# Usage: add_tar.sh <file> <pkgid> <flags>
# Requires a recent GNU tar for compression autodetect and xz support.


TMP=`mktemp -d manned.XXXXXXX`

# TODO: tar throws an error if there are no man pages. This isn't really an error, though.
tar --warning=no-unknown-keyword -C "$TMP" $3 -xf "$1" --wildcards '*/man/*'\
 && ./add_dir.pl "$TMP" "$2"
RET=$?

rm -rf "$TMP"
exit $RET

