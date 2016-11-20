#!/bin/sh

. ./common.sh

case "$1" in
  active)
    MIRROR=http://ftp.nluug.nl/pub/os/Linux/distr/archlinux
    REPOS="core extra community"
    for REPO in $REPOS; do
      index arch --sys arch --mirror $MIRROR --repo $REPO
    done
    ;;
esac
