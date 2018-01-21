#!/bin/sh

. ./common.sh

VMIRROR=http://vault.centos.org/
CMIRROR=http://centos.mirrors.ovh.net/ftp.centos.org/

# Centos 3.1 - 3.6 (doesn't have useful repo metadata)
centa() {
    local VER=$1
    index rpmdir --sys centos-$VER --cat os      --mirror "$VMIRROR$VER/os/i386/RedHat/RPMS/"
    index rpmdir --sys centos-$VER --cat os      --mirror "$VMIRROR$VER/updates/i386/RPMS/"
    index rpmdir --sys centos-$VER --cat extras  --mirror "$VMIRROR$VER/extras/i386/RPMS/"
    index rpmdir --sys centos-$VER --cat addons  --mirror "$VMIRROR$VER/addons/i386/RPMS/"
    index rpmdir --sys centos-$VER --cat contrib --mirror "$VMIRROR$VER/contrib/i386/RPMS/"
}

# Centos 3.7+ (same structure, but has more repos and metadata we can use)
centb() {
    local VER=$1
    local MIR=${2:-$VMIRROR}
    index rpm --sys centos-$VER --cat os         --mirror "$MIR$VER/os/i386/"
    index rpm --sys centos-$VER --cat os         --mirror "$MIR$VER/updates/i386/"
    index rpm --sys centos-$VER --cat extras     --mirror "$MIR$VER/extras/i386/"
    index rpm --sys centos-$VER --cat addons     --mirror "$MIR$VER/addons/i386/"  # not present in 6.0+
    index rpm --sys centos-$VER --cat contrib    --mirror "$MIR$VER/contrib/i386/" # not present in some 5.x releases
    index rpm --sys centos-$VER --cat centosplus --mirror "$MIR$VER/centosplus/i386/"
}

# CentOS 7.0+ (different versioning, using x86_64)
centc() {
    local VER=$1
    local DIR=$2
    local MIR=${3:-$VMIRROR}
    index rpm --sys centos-$VER --cat os         --mirror "$MIR$DIR/os/x86_64/"
    index rpm --sys centos-$VER --cat os         --mirror "$MIR$DIR/updates/x86_64/"
    index rpm --sys centos-$VER --cat extras     --mirror "$MIR$DIR/extras/x86_64/"
    index rpm --sys centos-$VER --cat centosplus --mirror "$MIR$DIR/centosplus/x86_64/"
}

case "$1" in
    2.1)
        index rpmdir --sys centos-2.1 --cat core --mirror "${VMIRROR}2.1/final/i386/CentOS/RPMS/"
        ;;
    3.1)
        centa 3.1
        ;;
    3.3)
        centa 3.3
        ;;
    3.4)
        centa 3.4
        ;;
    3.5)
        centa 3.5
        ;;
    3.6)
        centa 3.6
        ;;
    3.7)
        centb 3.7
        ;;
    3.8)
        centb 3.8
        ;;
    3.9)
        centb 3.9
        ;;
    4.0)
        centb 4.0
        ;;
    4.1)
        centb 4.1
        ;;
    4.2)
        centb 4.2
        ;;
    4.3)
        centb 4.3
        ;;
    4.4)
        centb 4.4
        ;;
    4.5)
        centb 4.5
        ;;
    4.6)
        centb 4.6
        ;;
    4.7)
        centb 4.7
        ;;
    4.8)
        centb 4.8
        ;;
    4.9)
        centb 4.9
        ;;
    5.0)
        centb 5.0
        ;;
    5.1)
        centb 5.1
        ;;
    5.2)
        centb 5.2
        ;;
    5.3)
        centb 5.3
        ;;
    5.4)
        centb 5.4
        ;;
    5.5)
        centb 5.5
        ;;
    5.6)
        centb 5.6
        ;;
    5.7)
        centb 5.7
        ;;
    5.8)
        centb 5.8
        ;;
    5.9)
        centb 5.9
        ;;
    5.10)
        centb 5.10
        ;;
    5.11)
        centb 5.11
        ;;
    6.0)
        centb 6.0
        ;;
    6.1)
        centb 6.1
        ;;
    6.2)
        centb 6.2
        ;;
    6.3)
        centb 6.3
        ;;
    6.4)
        centb 6.4
        ;;
    6.5)
        centb 6.5
        ;;
    6.6)
        centb 6.6
        ;;
    6.7)
        centb 6.7
        ;;
    6.8)
        centb 6.8
        ;;
    6.9)
        centb 6.9 $CMIRROR
        ;;
    7.0)
        centc 7.0 7.0.1406
        ;;
    7.1)
        centc 7.1 7.1.1503
        ;;
    7.2)
        centc 7.2 7.2.1511
        ;;
    7.3)
        centc 7.3 7.3.1611
        ;;
    7.4)
        centc 7.4 7.4.1708 $CMIRROR
        ;;
    old)
        $0 2.1
        $0 3.1
        $0 3.3
        $0 3.4
        $0 3.5
        $0 3.6
        $0 3.7
        $0 3.8
        $0 3.9
        $0 4.0
        $0 4.1
        $0 4.2
        $0 4.3
        $0 4.4
        $0 4.5
        $0 4.6
        $0 4.7
        $0 4.8
        $0 4.9
        $0 5.0
        $0 5.1
        $0 5.2
        $0 5.3
        $0 5.4
        $0 5.5
        $0 5.6
        $0 5.7
        $0 5.8
        $0 5.9
        $0 5.10
        $0 5.11
        $0 6.0
        $0 6.1
        $0 6.2
        $0 6.3
        $0 6.4
        $0 6.5
        $0 6.6
        $0 6.7
        $0 6.8
        $0 7.0
        $0 7.1
        $0 7.2
        $0 7.3
        ;;
    current)
        $0 6.9 # till 2020-11-30
        $0 7.4 # till 2024-06-30
        ;;
    all)
        $0 old
        $0 current
        ;;
esac
