#!/bin/sh

. ./common.sh

MIRROR=http://ftp.nluug.nl/pub/os/Linux/distr/archlinux

case "$1" in
    current)
        index arch --sys arch --mirror $MIRROR --repo core
        index arch --sys arch --mirror $MIRROR --repo extra
        index arch --sys arch --mirror $MIRROR --repo community
        ;;
esac
