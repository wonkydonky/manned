if test -f .config; then
    source .config
fi

INDEX="./indexer -vv"

set -x

arch() {
    local MIRROR=http://ftp.nluug.nl/pub/os/Linux/distr/archlinux
    local REPOS="core extra community"
    for REPO in $REPOS; do
      $INDEX arch --sys arch --mirror $MIRROR --repo $REPO
    done
}


daily() {
    arch
}

$@
