TMPDIR="/var/tmp/manned-indexer"

test -f .config && source ./.config


index() {
  echo "====> indexer -v $@"
  ./indexer -v $@ 2>&1
  echo
}


# Convenient wrapper around index() for debian repos
# TODO: Use x86_64 for new releases
# Usage: index_dev sys mirror distro list-of-components [contents]
#   contents:
#     empty for global Contents-i386.gz location
#     "cmp" for per-component Contents.i386.gz location
#     Otherwise, full path to Contents file
index_deb() {
  local SYS=$1
  local MIRROR=$2
  local DISTRO=$3
  local COMPONENTS=$4
  local CONTENTS=${5:-"dists/$DISTRO/Contents-i386.gz"}

  for CMP in $COMPONENTS; do
    local CONT=$CONTENTS
    test $CONT = cmp && CONT="dists/$DISTRO/$CMP/Contents-i386.gz"
    index deb --sys "$SYS" --mirror "$MIRROR" --contents "$MIRROR$CONT" --packages "${MIRROR}dists/$DISTRO/$CMP/binary-i386/Packages.gz"
  done
}
