#!/bin/sh

. ./common.sh

AMIRROR=http://old-releases.ubuntu.com/ubuntu/
CMIRROR=http://nl.archive.ubuntu.com/ubuntu/


# Shortcut for a standard Ubuntu repo, usage:
#   stdrepo name mirror arch
stdrepo() {
    local ARCH=${3:-"i386"}
    index_deb ubuntu-$1 $2 $1 "main multiverse restricted universe" "" $ARCH
    index_deb ubuntu-$1 $2 $1-updates "main multiverse restricted universe" "" $ARCH
    index_deb ubuntu-$1 $2 $1-security "main multiverse restricted universe" "" $ARCH
}


case $1 in
    warty)
        index_deb ubuntu-warty $AMIRROR warty "main multiverse restricted universe"
        index_deb ubuntu-warty $AMIRROR warty-updates "main multiverse restricted universe" "dists/warty/Contents-i386.gz"
        index_deb ubuntu-warty $AMIRROR warty-security "main multiverse restricted universe" "dists/warty/Contents-i386.gz"
        ;;
    hoary)
        index_deb ubuntu-hoary $AMIRROR hoary "main multiverse restricted universe"
        index_deb ubuntu-hoary $AMIRROR hoary-updates "main multiverse restricted universe" "dists/hoary/Contents-i386.gz"
        index_deb ubuntu-hoary $AMIRROR hoary-security "main multiverse restricted universe" "dists/hoary/Contents-i386.gz"
        ;;
    breezy)
        index_deb ubuntu-breezy $AMIRROR breezy "main multiverse restricted universe"
        index_deb ubuntu-breezy $AMIRROR breezy-updates "main multiverse restricted universe" "dists/breezy/Contents-i386.gz"
        index_deb ubuntu-breezy $AMIRROR breezy-security "main multiverse restricted universe" "dists/breezy/Contents-i386.gz"
        ;;
    dapper)
        # dists/dapper/ has an empty Contents-i386.gz; but that's handled properly (by downloading every package -.-).
        stdrepo dapper $AMIRROR
        ;;
    edgy)
        index_deb ubuntu-edgy $AMIRROR edgy "main multiverse restricted universe"
        index_deb ubuntu-edgy $AMIRROR edgy-updates "main multiverse restricted universe" "dists/edgy/Contents-i386.gz"
        index_deb ubuntu-edgy $AMIRROR edgy-security "main multiverse restricted universe" "dists/edgy/Contents-i386.gz"
        ;;
    feisty)
        stdrepo feisty $AMIRROR
        ;;
    gutsy)
        stdrepo gutsy $AMIRROR
        ;;
    hardy)
        stdrepo hardy $AMIRROR
        ;;
    intrepid)
        stdrepo intrepid $AMIRROR
        ;;
    jaunty)
        stdrepo jaunty $AMIRROR
        ;;
    karmic)
        stdrepo karmic $AMIRROR
        ;;
    lucid)
        stdrepo lucid $AMIRROR
        ;;
    maverick)
        stdrepo maverick $AMIRROR
        ;;
    natty)
        stdrepo natty $AMIRROR
        ;;
    oneiric)
        stdrepo oneiric $AMIRROR
        ;;
    precise)
        stdrepo precise $CMIRROR
        ;;
    quantal)
        stdrepo quantal $AMIRROR
        ;;
    raring)
        stdrepo raring $AMIRROR
        ;;
    saucy)
        stdrepo saucy $AMIRROR
        ;;
    trusty)
        stdrepo trusty $CMIRROR
        ;;
    utopic)
        stdrepo utopic $AMIRROR
        ;;
    vivid)
        stdrepo vivid $CMIRROR
        ;;
    wily)
        stdrepo wily $CMIRROR
        ;;
    xenial)
        stdrepo xenial $CMIRROR
        ;;
    yakkety)
        stdrepo yakkety $CMIRROR
        ;;
    zesty)
        stdrepo zesty $CMIRROR amd64
        ;;
    artful)
        stdrepo artful $CMIRROR amd64
        ;;
    old)
        $0 warty
        $0 hoary
        $0 breezy
        $0 dapper
        $0 edgy
        $0 feisty
        $0 gutsy
        $0 intrepid
        $0 jaunty
        $0 karmic
        $0 lucid
        $0 maverick
        $0 natty
        $0 hardy
        $0 oneiric
        $0 precise
        $0 raring
        $0 quantal
        $0 saucy
        $0 utopic
        $0 vivid
        $0 wily
        $0 yakkety
        ;;
    current)
        $0 trusty   # until 2019-04
        $0 xenial   # until 2021-04
        $0 zesty    # until 2018-01
        $0 artful   # until 2018-07
        ;;
    all)
        $0 old
        $0 current
        ;;
esac
