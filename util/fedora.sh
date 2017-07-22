#!/bin/sh

. ./common.sh

AMIRROR=http://archives.fedoraproject.org/pub/archive/fedora/linux/
CMIRROR=http://mirror.nl.leaseweb.net/fedora/linux/


# Fedora 7+ is pretty regular
fedora() { # release arch mirror
    MIR=$AMIRROR
    [ -n "$3" ] && MIR=$3
    index rpm --sys fedora-$1 --cat everything --mirror "${MIR}releases/$1/Everything/$2/os/"
    index rpm --sys fedora-$1 --cat everything --mirror "${MIR}updates/$1/$2/"
}


case "$1" in
    1)
        index rpmdir --sys fedora-1 --cat core   --mirror "${AMIRROR}core/1/i386/os/Fedora/RPMS/"
        ;;
    2)
        index rpm --sys fedora-2 --cat core   --mirror "${AMIRROR}core/2/i386/os/"
        ;;
    3)
        index rpm --sys fedora-3 --cat core   --mirror "${AMIRROR}core/3/i386/os/"
        index rpm --sys fedora-3 --cat extras --mirror "${AMIRROR}extras/3/i386/"
        ;;
    4)
        index rpm --sys fedora-4 --cat core   --mirror "${AMIRROR}core/4/i386/os/"
        index rpm --sys fedora-4 --cat extras --mirror "${AMIRROR}extras/4/i386/"
        ;;
    5)
        index rpm --sys fedora-5 --cat core   --mirror "${AMIRROR}core/5/i386/os/"
        index rpm --sys fedora-5 --cat extras --mirror "${AMIRROR}extras/5/i386/"
        ;;
    6)
        index rpm --sys fedora-6 --cat core   --mirror "${AMIRROR}core/6/i386/os/"
        index rpm --sys fedora-6 --cat extras --mirror "${AMIRROR}extras/6/i386/"
        ;;
    7)
        fedora 7 i386
        ;;
    8)
        fedora 8 i386
        ;;
    9)
        fedora 9 i386
        ;;
    10)
        fedora 10 i386
        ;;
    11)
        fedora 11 i386
        ;;
    12)
        fedora 12 i386
        ;;
    13)
        fedora 13 i386
        ;;
    14)
        fedora 14 i386
        ;;
    15)
        fedora 15 i386
        ;;
    16)
        fedora 16 i386
        ;;
    17)
        fedora 17 i386
        ;;
    18)
        fedora 18 x86_64
        ;;
    19)
        fedora 19 x86_64
        ;;
    20)
        fedora 20 x86_64
        ;;
    21)
        fedora 21 x86_64
        ;;
    22)
        fedora 22 x86_64
        ;;
    23)
        fedora 23 x86_64 $CMIRROR
        ;;
    24)
        fedora 24 x86_64 $CMIRROR
        ;;
    25)
        fedora 25 x86_64 $CMIRROR
        ;;
    26)
        fedora 26 x86_64 $CMIRROR
        ;;
    old)
        $0 1
        $0 2
        $0 3
        $0 4
        $0 5
        $0 6
        $0 7
        $0 8
        $0 9
        $0 10
        $0 11
        $0 12
        $0 13
        $0 14
        $0 15
        $0 16
        $0 17
        $0 18
        $0 19
        $0 20
        $0 21
        $0 22
        $0 23
        ;;
    current)
        $0 24
        $0 25
        $0 26
        ;;
    all)
        $0 old
        $0 current
        ;;
esac
