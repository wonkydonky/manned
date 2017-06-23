#!/bin/sh

. ./common.sh

AMIRROR=http://archive.debian.org/debian/
CMIRROR=http://ftp.nl.debian.org/debian/

# XXX: buzz and rex have some deb-old formatted packages, the indexer doesn't support these.

case "$1" in
    buzz)
        index deb --sys debian-buzz --mirror $AMIRROR --contents ${AMIRROR}dists/buzz/main/Contents.gz --packages ${AMIRROR}dists/buzz/main/binary-i386/Packages.gz
        index deb --sys debian-buzz --mirror $AMIRROR --contents ${AMIRROR}dists/buzz/contrib/Contents.gz --packages ${AMIRROR}dists/buzz/contrib/binary/Packages.gz
        ;;
    rex)
        index deb --sys debian-rex --mirror $AMIRROR --contents ${AMIRROR}dists/rex/main/Contents.gz --packages ${AMIRROR}dists/rex/main/binary-i386/Packages.gz
        index deb --sys debian-rex --mirror $AMIRROR --contents ${AMIRROR}dists/rex/contrib/Contents.gz --packages ${AMIRROR}dists/rex/contrib/binary/Packages.gz
        ;;
    bo)
        index deb --sys debian-bo --mirror $AMIRROR --contents ${AMIRROR}dists/bo/main/Contents-i386.gz --packages ${AMIRROR}dists/bo/main/binary-i386/Packages.gz
        # There's no Contents file for contrib and non-free
        index deb --sys debian-bo --mirror $AMIRROR --packages ${AMIRROR}dists/bo/contrib/binary/Packages.gz
        index deb --sys debian-bo --mirror $AMIRROR --packages ${AMIRROR}dists/bo/non-free/binary/Packages.gz
        ;;
    hamm)
        index_deb debian-hamm $AMIRROR hamm "main hamm contrib non-free"
        ;;
    slink)
        index_deb debian-slink $AMIRROR slink "main contrib non-free"
        ;;
    potato)
        index_deb debian-potato $AMIRROR potato "main contrib non-free"
        ;;
    woody)
        index_deb debian-woody $AMIRROR woody "main contrib non-free"
        ;;
    sarge)
        index_deb debian-sarge $AMIRROR sarge "main contrib non-free"
        ;;
    etch)
        index_deb debian-etch $AMIRROR etch "main contrib non-free"
        ;;
    lenny)
        index_deb debian-lenny $AMIRROR lenny "main contrib non-free"
        ;;
    squeeze)
        index_deb debian-squeeze $AMIRROR squeeze "main contrib non-free"
        index_deb debian-squeeze $AMIRROR squeeze-lts "main contrib non-free" cmp
        ;;
    wheezy)
        index_deb debian-wheezy $CMIRROR wheezy "main contrib non-free"
        index_deb debian-wheezy $CMIRROR wheezy-updates "main contrib non-free" cmp
        ;;
    jessie)
        index_deb debian-jessie $CMIRROR jessie "main contrib non-free" cmp
        index_deb debian-jessie $CMIRROR jessie-updates "main contrib non-free" cmp
        ;;
    stretch)
        index_deb debian-stretch $CMIRROR stretch "main contrib non-free" cmp
        index_deb debian-stretch $CMIRROR stretch-updates "main contrib non-free" cmp
        ;;
    old)
        $0 buzz
        $0 rex
        $0 bo
        $0 hamm
        $0 slink
        $0 potato
        $0 woody
        $0 sarge
        $0 etch
        $0 lenny
        $0 squeeze
        ;;
    current)
        $0 wheezy
        $0 jessie
        $0 stretch
        ;;
    all)
        $0 old
        $0 current
        ;;
esac
