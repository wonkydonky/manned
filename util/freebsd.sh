#!/bin/sh

. ./common.sh

AMIRROR=http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/
CMIRROR=http://ftp.dk.freebsd.org/pub/FreeBSD/releases/
PMIRROR=http://pkg.freebsd.org/

CURL="curl -fSs -A manual-page-crawler,info@manned.org"
SPLITTAR="$TMPDIR/freebsd-merged-tar"


# Index a "core" file. Simple wrapper around 'index pkg', with --ver = date,
# --cat="core", and support for split tar files.
index_core() { # <sys> <url-prefix> <pkgname> <date> <last-sequence>
    local FN=$2
    if [ -n "$5" ]; then
        # XXX: The annoying part about doing the tar merging here is that the
        # files are downloaded even if the indexer later decides that it
        # doesn't need to index this particular file, thus wasting bandwidth.
        echo "= Fetching $FN {aa .. $5}"
        $CURL "$FN{"`perl -le "print join ',', 'aa'..'$5'"`'}' >$SPLITTAR || return 1
        FN=$SPLITTAR
    fi
    index pkg --force --sys $1 --cat core --pkg $3 --ver $4 --date $4 $FN
}


case $1 in
    1.0)
        MIR="${AMIRROR}i386/1.0-RELEASE/"
        index_core freebsd-1.0 "${MIR}tarballs/bindist/bin_tgz."     core-bindist          1993-11-15 dc
        index_core freebsd-1.0 "${MIR}tarballs/xfree86/doc.tgz"      core-xfree86-doc      1993-10-25
        index_core freebsd-1.0 "${MIR}tarballs/xfree86/fontserv.tgz" core-xfree86-fontserv 1993-10-21
        index_core freebsd-1.0 "${MIR}tarballs/xfree86/man.tgz"      core-xfree86-man      1993-10-20
        index_core freebsd-1.0 "${MIR}tarballs/xfree86/pex.tgz"      core-xfree86-pex      1993-10-21
        # A few packages
        index pkg --sys freebsd-1.0 --cat packages --pkg emacs-19-19_bin --ver 1993-09-13 --date 1993-09-13 "${MIR}packages/emacs-19-19_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg f2c_bin         --ver 1993-10-01 --date 1993-10-01 "${MIR}packages/f2c_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg fileutils_bin   --ver 1993-10-06 --date 1993-10-06 "${MIR}packages/fileutils_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg ghostscript_bin --ver 1993-10-02 --date 1993-10-02 "${MIR}packages/ghostscript_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg gopher_bin      --ver 1993-10-15 --date 1993-10-15 "${MIR}packages/gopher_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg info-zip_bin    --ver 1993-09-04 --date 1993-09-04 "${MIR}packages/info-zip_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg jpeg_bin        --ver 1993-09-04 --date 1993-09-04 "${MIR}packages/jpeg_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg kermit_bin      --ver 1993-09-04 --date 1993-09-04 "${MIR}packages/kermit_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg ksh_bin         --ver 1993-09-04 --date 1993-09-04 "${MIR}packages/ksh_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg miscutils_bin   --ver 1993-09-06 --date 1993-09-06 "${MIR}packages/miscutils_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg mtools_bin      --ver 1993-08-30 --date 1993-08-30 "${MIR}packages/mtools_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg pbmplus_bin     --ver 1993-10-05 --date 1993-10-05 "${MIR}packages/pbmplus_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg pkg_install     --ver 1993-10-10 --date 1993-10-10 "${MIR}packages/pkg_install.tar.gz"
        index pkg --sys freebsd-1.0 --cat packages --pkg shellutils_bin  --ver 1993-10-06 --date 1993-10-06 "${MIR}packages/shellutils_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg tcl_bin         --ver 1993-09-18 --date 1993-09-18 "${MIR}packages/tcl_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg tcsh_bin        --ver 1993-09-04 --date 1993-09-04 "${MIR}packages/tcsh_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg textutils_bin   --ver 1993-09-05 --date 1993-09-05 "${MIR}packages/textutils_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg tk_bin          --ver 1993-09-18 --date 1993-09-18 "${MIR}packages/tk_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg urt_bin         --ver 1993-10-05 --date 1993-10-05 "${MIR}packages/urt_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg xlock_bin       --ver 1993-09-04 --date 1993-09-04 "${MIR}packages/xlock_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg xv_bin          --ver 1993-09-06 --date 1993-09-06 "${MIR}packages/xv_bin.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg xview32b        --ver 1993-09-16 --date 1993-09-16 "${MIR}packages/xview32b.tgz"
        index pkg --sys freebsd-1.0 --cat packages --pkg zsh_bin         --ver 1993-09-04 --date 1993-09-04 "${MIR}packages/zsh_bin.tgz"
        ;;
    2.0.5)
        MIR="${AMIRROR}i386/2.0.5-RELEASE/"
        index_core freebsd-2.0.5 "${MIR}des/des.aa"         core-des-des  1995-06-11
        index_core freebsd-2.0.5 "${MIR}des/krb."           core-des-krb  1995-06-11 ac
        index_core freebsd-2.0.5 "${MIR}manpages/manpages." core-manpages 1995-06-09 al
        ;;
    2.1.5)
        MIR="${AMIRROR}i386/2.1.5-RELEASE/"
        index_core freebsd-2.1.5 "${MIR}des/des.aa"         core-des-des  1996-07-16
        index_core freebsd-2.1.5 "${MIR}des/krb."           core-des-krb  1996-07-16 ac
        index_core freebsd-2.1.5 "${MIR}manpages/manpages." core-manpages 1996-07-16 am
        ;;
    2.1.7)
        MIR="${AMIRRPR}i386/2.1.7-RELEASE/"
        index_core freebsd-2.1.7 "${MIR}des/des.aa"         core-des-des  1997-02-19
        index_core freebsd-2.1.7 "${MIR}des/krb."           core-des-krb  1997-02-19 ac
        index_core freebsd-2.1.7 "${MIR}manpages/manpages." core-manpages 1997-02-19 am
        ;;
    2.2.2)
        MIR="${AMIRROR}i386/2.2.2-RELEASE/"
        index_core freebsd-2.2.2 "${MIR}des/des."           core-des-des  1997-05-20 ab
        index_core freebsd-2.2.2 "${MIR}des/krb."           core-des-krb  1997-05-20 ac
        index_core freebsd-2.2.2 "${MIR}manpages/manpages." core-manpages 1997-05-20 ap
        ;;
    2.2.5)
        MIR="${AMIRROR}i386/2.2.5-RELEASE/"
        index_core freebsd-2.2.5 "${MIR}des/des."           core-des-des  1997-10-22 ab
        index_core freebsd-2.2.5 "${MIR}des/krb."           core-des-krb  1997-10-22 ad
        index_core freebsd-2.2.5 "${MIR}manpages/manpages." core-manpages 1997-10-22 an
        ;;
    2.2.6)
        MIR="${AMIRROR}i386/2.2.6-RELEASE/"
        index_core freebsd-2.2.6 "${MIR}des/des."           core-des-des  1998-03-25 ab
        index_core freebsd-2.2.6 "${MIR}des/krb."           core-des-krb  1998-03-25 ad
        index_core freebsd-2.2.6 "${MIR}manpages/manpages." core-manpages 1998-03-25 ao
        ;;
    2.2.7)
        MIR="${AMIRROR}i386/2.2.7-RELEASE/"
        index_core freebsd-2.2.7 "${MIR}des/des."             core-des-des          1998-07-22 ab
        index_core freebsd-2.2.7 "${MIR}des/krb."             core-des-krb          1998-07-22 ad
        index_core freebsd-2.2.7 "${MIR}manpages/manpages."   core-manpages         1998-07-22 ao
        index_core freebsd-2.2.7 "${MIR}XF86332/X332fsrv.tgz" core-XF86332-X332fsrv 1998-03-01
        index_core freebsd-2.2.7 "${MIR}XF86332/X332man.tgz"  core-XF86332-X332man  1998-03-01
        index_core freebsd-2.2.7 "${MIR}XF86332/X332set.tgz"  core-XF86332-X332set  1998-03-01
        ;;
    2.2.8)
        MIR="${AMIRROR}i386/2.2.8-RELEASE/"
        index_core freebsd-2.2.8 "${MIR}des/des."           core-des-des       1998-11-29 ab
        index_core freebsd-2.2.8 "${MIR}des/krb."           core-des-krb       1998-11-29 ad
        index_core freebsd-2.2.8 "${MIR}manpages/manpages." core-manpages      1998-11-29 ax
        index_core freebsd-2.2.8 "${MIR}XF86333/Xfsrv.tgz"  core-XF86333-Xfsrv 1998-11-14
        index_core freebsd-2.2.8 "${MIR}XF86333/Xman.tgz"   core-XF86333-Xman  1998-11-14
        index_core freebsd-2.2.8 "${MIR}XF86333/Xset.tgz"   core-XF86333-Xset  1998-11-14
        index freebsd1 --sys freebsd-2.2.8 --arch i386 --mirror "${MIR}packages/"
        ;;
    3.0)
        MIR="${AMIRROR}i386/3.0-RELEASE/"
        index_core freebsd-3.0 "${MIR}bin/bin."           core-bin           1998-10-16 es
        index_core freebsd-3.0 "${MIR}des/des."           core-des-des       1998-10-16 ab
        index_core freebsd-3.0 "${MIR}des/krb."           core-des-krb       1998-10-16 ae
        index_core freebsd-3.0 "${MIR}manpages/manpages." core-manpages      1998-10-16 bb
        index_core freebsd-3.0 "${MIR}XF86332/Xfsrv.tgz"  core-XF86332-Xfsrv 1998-09-28
        index_core freebsd-3.0 "${MIR}XF86332/Xman.tgz"   core-XF86332-Xman  1998-09-28
        index_core freebsd-3.0 "${MIR}XF86332/Xset.tgz"   core-XF86332-Xset  1998-09-28
        ;;
    3.1)
        MIR="${AMIRROR}i386/3.1-RELEASE/"
        index_core freebsd-3.1 "${MIR}bin/bin."           core-bin           1999-02-15 dx
        index_core freebsd-3.1 "${MIR}des/des."           core-des-des       1999-02-15 ab
        index_core freebsd-3.1 "${MIR}des/krb."           core-des-krb       1999-02-15 ae
        index_core freebsd-3.1 "${MIR}manpages/manpages." core-manpages      1999-02-15 be
        index_core freebsd-3.1 "${MIR}XF86332/Xfsrv.tgz"  core-XF86332-Xfsrv 1999-02-15
        index_core freebsd-3.1 "${MIR}XF86332/Xman.tgz"   core-XF86332-Xman  1999-02-15
        index_core freebsd-3.1 "${MIR}XF86332/Xset.tgz"   core-XF86332-Xset  1999-02-15
        ;;
    3.2)
        MIR="${AMIRROR}i386/3.2-RELEASE/"
        index_core freebsd-3.2 "${MIR}bin/bin."           core-bin           1999-05-18 eb
        index_core freebsd-3.2 "${MIR}des/des."           core-des-des       1999-05-18 ab
        index_core freebsd-3.2 "${MIR}des/krb."           core-des-krb       1999-05-18 ae
        index_core freebsd-3.2 "${MIR}manpages/manpages." core-manpages      1999-05-18 be
        index_core freebsd-3.2 "${MIR}XF86333/Xfsrv.tgz"  core-XF86333-Xfsrv 1998-11-14
        index_core freebsd-3.2 "${MIR}XF86333/Xman.tgz"   core-XF86333-Xman  1998-11-14
        index_core freebsd-3.2 "${MIR}XF86333/Xset.tgz"   core-XF86333-Xset  1998-11-14
        ;;
    3.3)
        MIR="${AMIRROR}i386/3.3-RELEASE/"
        index_core freebsd-3.3 "${MIR}bin/bin."           core-bin           1999-09-17 ec
        index_core freebsd-3.3 "${MIR}des/des."           core-des-des       1999-09-17 ab
        index_core freebsd-3.3 "${MIR}des/krb."           core-des-krb       1999-09-17 ae
        index_core freebsd-3.3 "${MIR}manpages/manpages." core-manpages      1999-09-17 au
        index_core freebsd-3.3 "${MIR}XF86335/Xfsrv.tgz"  core-XF86335-Xfsrv 1999-08-31
        index_core freebsd-3.3 "${MIR}XF86335/Xman.tgz"   core-XF86335-Xman  1999-08-31
        index_core freebsd-3.3 "${MIR}XF86335/Xset.tgz"   core-XF86335-Xset  1999-08-31
        ;;
    3.4)
        MIR="${AMIRROR}i386/3.4-RELEASE/"
        index_core freebsd-3.4 "${MIR}bin/bin."           core-bin           1999-12-20 ef
        index_core freebsd-3.4 "${MIR}des/des."           core-des-des       1999-12-20 ac
        index_core freebsd-3.4 "${MIR}des/krb."           core-des-krb       1999-12-20 ae
        index_core freebsd-3.4 "${MIR}manpages/manpages." core-manpages      1999-12-20 av
        index_core freebsd-3.4 "${MIR}XF86335/Xfsrv.tgz"  core-XF86335-Xfsrv 1999-08-31
        index_core freebsd-3.4 "${MIR}XF86335/Xman.tgz"   core-XF86335-Xman  1999-08-31
        index_core freebsd-3.4 "${MIR}XF86335/Xset.tgz"   core-XF86335-Xset  1999-08-31
        index freebsd1 --sys freebsd-3.4 --arch i386 --mirror "${MIR}packages/"
        ;;
    3.5)
        MIR="${AMIRROR}i386/3.5-RELEASE/"
        index_core freebsd-3.5 "${MIR}bin/bin."           core-bin           2000-06-22 eg
        index_core freebsd-3.5 "${MIR}des/des."           core-des-des       2000-06-22 ac
        index_core freebsd-3.5 "${MIR}des/krb."           core-des-krb       2000-06-22 ae
        index_core freebsd-3.5 "${MIR}manpages/manpages." core-manpages      2000-06-22 av
        index_core freebsd-3.5 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2000-01-08
        index_core freebsd-3.5 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2000-01-08
        index_core freebsd-3.5 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2000-01-08
        index freebsd1 --sys freebsd-3.5 --arch i386 --mirror "${MIR}packages/"
        ;;
    3.5.1)
        MIR="${AMIRROR}i386/3.5.1-RELEASE/"
        index_core freebsd-3.5.1 "${MIR}bin/bin."           core-bin           2000-07-20 eg
        index_core freebsd-3.5.1 "${MIR}des/des."           core-des-des       2000-07-20 ac
        index_core freebsd-3.5.1 "${MIR}des/krb."           core-des-krb       2000-07-20 ae
        index_core freebsd-3.5.1 "${MIR}manpages/manpages." core-manpages      2000-07-20 av
        index_core freebsd-3.5.1 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2000-01-08
        index_core freebsd-3.5.1 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2000-01-08
        index_core freebsd-3.5.1 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2000-01-08
        index freebsd1 --sys freebsd-3.5.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.0)
        MIR="${AMIRROR}i386/4.0-RELEASE/"
        index_core freebsd-4.0 "${MIR}bin/bin."           core-bin           2000-03-20 ev
        index_core freebsd-4.0 "${MIR}crypto/crypto."     core-crypto        2000-03-20 aj
        index_core freebsd-4.0 "${MIR}crypto/krb4."       core-crypto-krb4   2000-03-20 ae
        index_core freebsd-4.0 "${MIR}crypto/krb5."       core-crypto-krb5   2000-03-20 ad
        index_core freebsd-4.0 "${MIR}games/games."       core-games         2000-03-20 ak
        index_core freebsd-4.0 "${MIR}manpages/manpages." core-manpages      2000-03-20 aw
        index_core freebsd-4.0 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2001-03-22
        index_core freebsd-4.0 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2001-03-22
        index_core freebsd-4.0 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2001-03-22
        ;;
    4.1)
        MIR="${AMIRROR}i386/4.1-RELEASE/"
        index_core freebsd-4.1 "${MIR}bin/bin."           core-bin           2000-07-27 fb
        index_core freebsd-4.1 "${MIR}crypto/crypto."     core-crypto        2000-07-27 aj
        index_core freebsd-4.1 "${MIR}crypto/krb4."       core-crypto-krb4   2000-07-27 ae
        index_core freebsd-4.1 "${MIR}crypto/krb5."       core-crypto-krb5   2000-07-27 ad
        index_core freebsd-4.1 "${MIR}games/games."       core-games         2000-07-27 ak
        index_core freebsd-4.1 "${MIR}manpages/manpages." core-manpages      2000-07-27 ax
        index_core freebsd-4.1 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2000-07-25
        index_core freebsd-4.1 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2000-07-25
        index_core freebsd-4.1 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2000-07-25
        ;;
    4.1.1)
        MIR="${AMIRROR}i386/4.1.1-RELEASE/"
        index_core freebsd-4.1.1 "${MIR}bin/bin."           core-bin           2000-09-25 fc
        index_core freebsd-4.1.1 "${MIR}crypto/crypto."     core-crypto        2000-09-25 ak
        index_core freebsd-4.1.1 "${MIR}crypto/krb4."       core-crypto-krb4   2000-09-25 ae
        index_core freebsd-4.1.1 "${MIR}crypto/krb5."       core-crypto-krb5   2000-09-25 ad
        index_core freebsd-4.1.1 "${MIR}games/games."       core-games         2000-09-25 ak
        index_core freebsd-4.1.1 "${MIR}manpages/manpages." core-manpages      2000-09-25 ax
        index_core freebsd-4.1.1 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2000-07-25
        index_core freebsd-4.1.1 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2000-07-25
        index_core freebsd-4.1.1 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2000-07-25
        index freebsd1 --sys freebsd-4.1.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.2)
        MIR="${AMIRROR}i386/4.2-RELEASE/"
        index_core freebsd-4.2 "${MIR}bin/bin."           core-bin           2000-11-21 fc
        index_core freebsd-4.2 "${MIR}crypto/crypto."     core-crypto        2000-11-21 al
        index_core freebsd-4.2 "${MIR}crypto/krb4."       core-crypto-krb4   2000-11-21 ae
        index_core freebsd-4.2 "${MIR}crypto/krb5."       core-crypto-krb5   2000-11-21 ad
        index_core freebsd-4.2 "${MIR}games/games."       core-games         2000-11-21 ak
        index_core freebsd-4.2 "${MIR}manpages/manpages." core-manpages      2000-11-21 ax
        index_core freebsd-4.2 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2000-07-25
        index_core freebsd-4.2 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2000-07-25
        index_core freebsd-4.2 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2000-07-25
        index freebsd1 --sys freebsd-4.2 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.3)
        MIR="${AMIRROR}i386/4.3-RELEASE/"
        index_core freebsd-4.3 "${MIR}bin/bin."           core-bin           2001-04-20 fg
        index_core freebsd-4.3 "${MIR}crypto/crypto."     core-crypto        2001-04-20 al
        index_core freebsd-4.3 "${MIR}crypto/krb4."       core-crypto-krb4   2001-04-20 ae
        index_core freebsd-4.3 "${MIR}crypto/krb5."       core-crypto-krb5   2001-04-20 ae
        index_core freebsd-4.3 "${MIR}games/games."       core-games         2001-04-20 ak
        index_core freebsd-4.3 "${MIR}manpages/manpages." core-manpages      2001-04-20 ay
        index_core freebsd-4.3 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2001-03-22
        index_core freebsd-4.3 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2001-03-22
        index_core freebsd-4.3 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2001-03-22
        index freebsd1 --sys freebsd-4.3 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.4)
        MIR="${AMIRROR}i386/4.4-RELEASE/"
        index_core freebsd-4.4 "${MIR}bin/bin."           core-bin           2001-09-20 fk
        index_core freebsd-4.4 "${MIR}crypto/crypto."     core-crypto        2001-09-20 ak
        index_core freebsd-4.4 "${MIR}crypto/krb4."       core-crypto-krb4   2001-09-20 ae
        index_core freebsd-4.4 "${MIR}crypto/krb5."       core-crypto-krb5   2001-09-20 ad
        index_core freebsd-4.4 "${MIR}games/games."       core-games         2001-09-20 ak
        index_core freebsd-4.4 "${MIR}manpages/manpages." core-manpages      2001-09-20 az
        index_core freebsd-4.4 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2001-09-05
        index_core freebsd-4.4 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2001-09-05
        index_core freebsd-4.4 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2001-09-05
        index freebsd1 --sys freebsd-4.4 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.5)
        MIR="${AMIRROR}i386/4.5-RELEASE/"
        index_core freebsd-4.5 "${MIR}bin/bin."           core-bin           2002-01-29 fm
        index_core freebsd-4.5 "${MIR}crypto/crypto."     core-crypto        2002-01-29 al
        index_core freebsd-4.5 "${MIR}crypto/krb4."       core-crypto-krb4   2002-01-29 ae
        index_core freebsd-4.5 "${MIR}crypto/krb5."       core-crypto-krb5   2002-01-29 ae
        index_core freebsd-4.5 "${MIR}games/games."       core-games         2002-01-29 ak
        index_core freebsd-4.5 "${MIR}manpages/manpages." core-manpages      2002-01-29 az
        index_core freebsd-4.5 "${MIR}XF86336/Xfsrv.tgz"  core-XF86336-Xfsrv 2002-01-08
        index_core freebsd-4.5 "${MIR}XF86336/Xman.tgz"   core-XF86336-Xman  2002-01-08
        index_core freebsd-4.5 "${MIR}XF86336/Xset.tgz"   core-XF86336-Xset  2002-01-08
        index freebsd1 --sys freebsd-4.5 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.6)
        MIR="${AMIRROR}i386/4.6-RELEASE/"
        index_core freebsd-4.6 "${MIR}bin/bin."           core-bin         2002-06-15 fp
        index_core freebsd-4.6 "${MIR}crypto/crypto."     core-crypto      2002-06-15 al
        index_core freebsd-4.6 "${MIR}crypto/krb4."       core-crypto-krb4 2002-06-15 ae
        index_core freebsd-4.6 "${MIR}crypto/krb5."       core-crypto-krb5 2002-06-15 ae
        index_core freebsd-4.6 "${MIR}games/games."       core-games       2002-06-15 ak
        index_core freebsd-4.6 "${MIR}manpages/manpages." core-manpages    2002-06-15 az
        index freebsd1 --sys freebsd-4.6 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.6.2)
        MIR="${AMIRROR}i386/4.6.2-RELEASE/"
        index_core freebsd-4.6.2 "${MIR}bin/bin."           core-bin         2002-08-15 fq
        index_core freebsd-4.6.2 "${MIR}crypto/crypto."     core-crypto      2002-08-15 am
        index_core freebsd-4.6.2 "${MIR}crypto/krb4."       core-crypto-krb4 2002-08-15 ae
        index_core freebsd-4.6.2 "${MIR}crypto/krb5."       core-crypto-krb5 2002-08-15 ae
        index_core freebsd-4.6.2 "${MIR}games/games."       core-games       2002-08-15 ak
        index_core freebsd-4.6.2 "${MIR}manpages/manpages." core-manpages    2002-08-15 az
        index freebsd1 --sys freebsd-4.6.2 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.7)
        MIR="${AMIRROR}i386/4.7-RELEASE/"
        index_core freebsd-4.7 "${MIR}bin/bin."           core-bin         2002-10-10 fr
        index_core freebsd-4.7 "${MIR}crypto/crypto."     core-crypto      2002-10-10 an
        index_core freebsd-4.7 "${MIR}crypto/krb4."       core-crypto-krb4 2002-10-10 af
        index_core freebsd-4.7 "${MIR}crypto/krb5."       core-crypto-krb5 2002-10-10 af
        index_core freebsd-4.7 "${MIR}games/games."       core-games       2002-10-10 ak
        index_core freebsd-4.7 "${MIR}manpages/manpages." core-manpages    2002-10-10 bc
        index freebsd1 --sys freebsd-4.7 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.8)
        MIR="${AMIRROR}i386/4.8-RELEASE/"
        index_core freebsd-4.8 "${MIR}bin/bin."           core-bin         2003-04-03 ft
        index_core freebsd-4.8 "${MIR}crypto/crypto."     core-crypto      2003-04-03 au
        index_core freebsd-4.8 "${MIR}crypto/krb4."       core-crypto-krb4 2003-04-03 ag
        index_core freebsd-4.8 "${MIR}crypto/krb5."       core-crypto-krb5 2003-04-03 af
        index_core freebsd-4.8 "${MIR}games/games."       core-games       2003-04-03 ak
        index_core freebsd-4.8 "${MIR}manpages/manpages." core-manpages    2003-04-03 bd
        index freebsd1 --sys freebsd-4.8 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.9)
        MIR="${AMIRROR}i386/4.9-RELEASE/"
        index_core freebsd-4.9 "${MIR}bin/bin."           core-bin         2003-10-28 fv
        index_core freebsd-4.9 "${MIR}crypto/crypto."     core-crypto      2003-10-28 au
        index_core freebsd-4.9 "${MIR}crypto/krb4."       core-crypto-krb4 2003-10-28 ag
        index_core freebsd-4.9 "${MIR}crypto/krb5."       core-crypto-krb5 2003-10-28 af
        index_core freebsd-4.9 "${MIR}games/games."       core-games       2003-10-28 ak
        index_core freebsd-4.9 "${MIR}manpages/manpages." core-manpages    2003-10-28 bd
        index freebsd1 --sys freebsd-4.9 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.10)
        MIR="${AMIRROR}i386/4.10-RELEASE/"
        index_core freebsd-4.10 "${MIR}bin/bin."           core-bin         2004-05-27 fw
        index_core freebsd-4.10 "${MIR}crypto/crypto."     core-crypto      2004-05-27 au
        index_core freebsd-4.10 "${MIR}crypto/krb4."       core-crypto-krb4 2004-05-27 ag
        index_core freebsd-4.10 "${MIR}crypto/krb5."       core-crypto-krb5 2004-05-27 af
        index_core freebsd-4.10 "${MIR}games/games."       core-games       2004-05-27 ak
        index_core freebsd-4.10 "${MIR}manpages/manpages." core-manpages    2004-05-27 bd
        index freebsd1 --sys freebsd-4.10 --arch i386 --mirror "${MIR}packages/"
        ;;
    4.11)
        MIR="${AMIRROR}i386/4.11-RELEASE/"
        index_core freebsd-4.11 "${MIR}bin/bin."           core-bin         2005-01-25 fx
        index_core freebsd-4.11 "${MIR}crypto/crypto."     core-crypto      2005-01-25 au
        index_core freebsd-4.11 "${MIR}crypto/krb4."       core-crypto-krb4 2005-01-25 ag
        index_core freebsd-4.11 "${MIR}crypto/krb5."       core-crypto-krb5 2005-01-25 af
        index_core freebsd-4.11 "${MIR}games/games."       core-games       2005-01-25 ak
        index_core freebsd-4.11 "${MIR}manpages/manpages." core-manpages    2005-01-25 be
        index freebsd1 --sys freebsd-4.11 --arch i386 --mirror "${MIR}packages/"
        ;;
    5.0)
        MIR="${AMIRROR}i386/5.0-RELEASE/"
        index_core freebsd-5.0 "${MIR}crypto/crypto."     core-crypto      2003-01-14 an
        index_core freebsd-5.0 "${MIR}crypto/krb4."       core-crypto-krb4 2003-01-14 af
        index_core freebsd-5.0 "${MIR}crypto/krb5."       core-crypto-krb5 2003-01-14 ag
        index_core freebsd-5.0 "${MIR}games/games."       core-games       2003-01-14 ag
        index_core freebsd-5.0 "${MIR}manpages/manpages." core-manpages    2003-01-14 ay
        index freebsd1 --sys freebsd-5.0 --arch i386 --mirror "${MIR}packages/"
        ;;
    5.1)
        MIR="${AMIRROR}i386/5.1-RELEASE/"
        index_core freebsd-5.1 "${MIR}crypto/crypto."     core-crypto      2003-06-09 ae
        index_core freebsd-5.1 "${MIR}crypto/krb5.aa"     core-crypto-krb5 2003-06-09
        index_core freebsd-5.1 "${MIR}games/games."       core-games       2003-06-09 ab
        index_core freebsd-5.1 "${MIR}manpages/manpages." core-manpages    2003-06-09 ae
        index freebsd1 --sys freebsd-5.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    5.2)
        MIR="${AMIRROR}i386/5.2-RELEASE/"
        index_core freebsd-5.2 "${MIR}crypto/crypto."     core-crypto      2004-01-09 ae
        index_core freebsd-5.2 "${MIR}crypto/krb5.aa"     core-crypto-krb5 2004-01-09
        index_core freebsd-5.2 "${MIR}games/games."       core-games       2004-01-09 ab
        index_core freebsd-5.2 "${MIR}manpages/manpages." core-manpages    2004-01-09 ae
        index freebsd1 --sys freebsd-5.2 --arch i386 --mirror "${MIR}packages/"
        ;;
    5.2.1)
        MIR="${AMIRROR}i386/5.2.1-RELEASE/"
        index_core freebsd-5.2.1 "${MIR}crypto/crypto."     core-crypto      2004-02-25 ae
        index_core freebsd-5.2.1 "${MIR}crypto/krb5.aa"     core-crypto-krb5 2004-02-25
        index_core freebsd-5.2.1 "${MIR}games/games."       core-games       2004-02-25 ab
        index_core freebsd-5.2.1 "${MIR}manpages/manpages." core-manpages    2004-02-25 ae
        index freebsd1 --sys freebsd-5.2.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    5.3)
        MIR="${AMIRROR}i386/5.3-RELEASE/"
        index_core freebsd-5.3 "${MIR}base/base."         core-base     2004-11-06 bg
        index_core freebsd-5.3 "${MIR}games/games."       core-games    2004-11-06 ab
        index_core freebsd-5.3 "${MIR}manpages/manpages." core-manpages 2004-11-06 ae
        index freebsd1 --sys freebsd-5.3 --arch i386 --mirror "${MIR}packages/"
        ;;
    5.4)
        MIR="${AMIRROR}i386/5.4-RELEASE/"
        index_core freebsd-5.4 "${MIR}base/base."         core-base     2005-05-09 bg
        index_core freebsd-5.4 "${MIR}games/games."       core-games    2005-05-09 ab
        index_core freebsd-5.4 "${MIR}manpages/manpages." core-manpages 2005-05-09 ae
        index freebsd1 --sys freebsd-5.4 --arch i386 --mirror "${MIR}packages/"
        ;;
    5.5)
        MIR="${AMIRROR}i386/5.5-RELEASE/"
        index_core freebsd-5.5 "${MIR}base/base."         core-base     2006-05-25 bg
        index_core freebsd-5.5 "${MIR}games/games."       core-games    2006-05-25 ab
        index_core freebsd-5.5 "${MIR}manpages/manpages." core-manpages 2006-05-25 ae
        index freebsd1 --sys freebsd-5.5 --arch i386 --mirror "${MIR}packages/"
        ;;
    6.0)
        MIR="${AMIRROR}i386/6.0-RELEASE/"
        index_core freebsd-6.0 "${MIR}base/base."         core-base     2005-11-04 bp
        index_core freebsd-6.0 "${MIR}games/games."       core-games    2005-11-04 ab
        index_core freebsd-6.0 "${MIR}manpages/manpages." core-manpages 2005-11-04 af
        index freebsd1 --sys freebsd-6.0 --arch i386 --mirror "${MIR}packages/"
        ;;
    6.1)
        MIR="${AMIRROR}i386/6.1-RELEASE/"
        index_core freebsd-6.1 "${MIR}base/base."         core-base     2006-05-08 bd
        index_core freebsd-6.1 "${MIR}games/games."       core-games    2006-05-08 ab
        index_core freebsd-6.1 "${MIR}manpages/manpages." core-manpages 2006-05-08 af
        index freebsd1 --sys freebsd-6.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    6.2)
        MIR="${AMIRROR}i386/6.2-RELEASE/"
        index_core freebsd-6.2 "${MIR}base/base."         core-base     2007-01-15 bd
        index_core freebsd-6.2 "${MIR}games/games."       core-games    2007-01-15 ab
        index_core freebsd-6.2 "${MIR}manpages/manpages." core-manpages 2007-01-15 af
        index freebsd1 --sys freebsd-6.2 --arch i386 --mirror "${MIR}packages/"
        ;;
    6.3)
        MIR="${AMIRROR}i386/6.3-RELEASE/"
        index_core freebsd-6.3 "${MIR}base/base."         core-base     2008-01-18 be
        index_core freebsd-6.3 "${MIR}games/games."       core-games    2008-01-18 ab
        index_core freebsd-6.3 "${MIR}manpages/manpages." core-manpages 2008-01-18 af
        index freebsd1 --sys freebsd-6.3 --arch i386 --mirror "${MIR}packages/"
        ;;
    6.4)
        MIR="${AMIRROR}i386/6.4-RELEASE/"
        index_core freebsd-6.4 "${MIR}base/base."         core-base     2008-11-28 be
        index_core freebsd-6.4 "${MIR}games/games."       core-games    2008-11-28 ab
        index_core freebsd-6.4 "${MIR}manpages/manpages." core-manpages 2008-11-28 af
        index freebsd1 --sys freebsd-6.4 --arch i386 --mirror "${MIR}packages/"
        ;;
    7.0)
        MIR="${AMIRROR}i386/7.0-RELEASE/"
        index_core freebsd-7.0 "${MIR}base/base."         core-base     2008-02-27 bh
        index_core freebsd-7.0 "${MIR}games/games."       core-games    2008-02-27 ab
        index_core freebsd-7.0 "${MIR}manpages/manpages." core-manpages 2008-02-27 af
        index freebsd1 --sys freebsd-7.0 --arch i386 --mirror "${MIR}packages/"
        ;;
    7.1)
        MIR="${AMIRROR}i386/7.1-RELEASE/"
        index_core freebsd-7.1 "${MIR}base/base."         core-base     2009-01-04 bi
        index_core freebsd-7.1 "${MIR}games/games."       core-games    2009-01-04 ab
        index_core freebsd-7.1 "${MIR}manpages/manpages." core-manpages 2009-01-04 af
        index freebsd1 --sys freebsd-7.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    7.2)
        MIR="${AMIRROR}i386/7.2-RELEASE/"
        index_core freebsd-7.2 "${MIR}base/base."         core-base     2009-05-04 bi
        index_core freebsd-7.2 "${MIR}games/games."       core-games    2009-05-04 ab
        index_core freebsd-7.2 "${MIR}manpages/manpages." core-manpages 2009-05-04 af
        index freebsd1 --sys freebsd-7.2 --arch i386 --mirror "${MIR}packages/"
        ;;
    7.3)
        MIR="${AMIRROR}i386/7.3-RELEASE/"
        index_core freebsd-7.3 "${MIR}base/base."         core-base     2010-03-23 bi
        index_core freebsd-7.3 "${MIR}games/games."       core-games    2010-03-23 ab
        index_core freebsd-7.3 "${MIR}manpages/manpages." core-manpages 2010-03-23 af
        index freebsd1 --sys freebsd-7.3 --arch i386 --mirror "${MIR}packages/"
        ;;
    7.4)
        MIR="${AMIRROR}i386/7.4-RELEASE/"
        index_core freebsd-7.4 "${MIR}base/base."         core-base     2011-02-24 bi
        index_core freebsd-7.4 "${MIR}games/games."       core-games    2011-02-24 ab
        index_core freebsd-7.4 "${MIR}manpages/manpages." core-manpages 2011-02-24 af
        index freebsd1 --sys freebsd-7.4 --arch i386 --mirror "${MIR}packages/"
        ;;
    8.0)
        MIR="${AMIRROR}i386/8.0-RELEASE/"
        index_core freebsd-8.0 "${MIR}base/base."         core-base     2009-11-25 bl
        index_core freebsd-8.0 "${MIR}games/games."       core-games    2009-11-25 ab
        index_core freebsd-8.0 "${MIR}manpages/manpages." core-manpages 2009-11-25 af
        index freebsd1 --sys freebsd-8.0 --arch i386 --mirror "${MIR}packages/"
        ;;
    8.1)
        MIR="${AMIRROR}i386/8.1-RELEASE/"
        index_core freebsd-8.1 "${MIR}base/base."         core-base     2010-07-23 bl
        index_core freebsd-8.1 "${MIR}games/games."       core-games    2010-07-23 ab
        index_core freebsd-8.1 "${MIR}manpages/manpages." core-manpages 2010-07-23 ag
        index freebsd1 --sys freebsd-8.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    8.2)
        MIR="${AMIRROR}i386/8.2-RELEASE/"
        index_core freebsd-8.2 "${MIR}base/base."         core-base     2011-02-24 bm
        index_core freebsd-8.2 "${MIR}games/games."       core-games    2011-02-24 ab
        index_core freebsd-8.2 "${MIR}manpages/manpages." core-manpages 2011-02-24 ag
        index freebsd1 --sys freebsd-8.2 --arch i386 --mirror "${MIR}packages/"
        ;;
    8.3)
        MIR="${AMIRROR}i386/8.3-RELEASE/"
        index_core freebsd-8.3 "${MIR}base/base."         core-base     2012-04-18 bm
        index_core freebsd-8.3 "${MIR}games/games."       core-games    2012-04-18 ab
        index_core freebsd-8.3 "${MIR}manpages/manpages." core-manpages 2012-04-18 ag
        index freebsd1 --sys freebsd-8.3 --arch i386 --mirror "${MIR}packages/"
        ;;
    8.4)
        MIR="${AMIRROR}i386/8.4-RELEASE/"
        index_core freebsd-8.4 "${MIR}base/base."         core-base     2013-06-07 bq
        index_core freebsd-8.4 "${MIR}games/games."       core-games    2013-06-07 ab
        index_core freebsd-8.4 "${MIR}manpages/manpages." core-manpages 2013-06-07 ag
        index freebsd1 --sys freebsd-8.4 --arch i386 --mirror "${MIR}packages/"
        ;;
    9.0)
        MIR="${AMIRROR}i386/9.0-RELEASE/"
        index_core freebsd-9.0 "${MIR}base.txz"  core-base  2012-01-12
        index_core freebsd-9.0 "${MIR}games.txz" core-games 2012-01-12
        index freebsd1 --sys freebsd-9.0 --arch i386 --mirror "${MIR}packages/"
        ;;
    9.1)
        MIR="${AMIRROR}i386/9.1-RELEASE/"
        index_core freebsd-9.1 "${MIR}base.txz"  core-base  2012-12-30
        index_core freebsd-9.1 "${MIR}games.txz" core-games 2012-12-30
        index freebsd1 --sys freebsd-9.1 --arch i386 --mirror "${MIR}packages/"
        ;;
    9.2)
        MIR="${AMIRROR}i386/9.2-RELEASE/"
        index_core freebsd-9.2 "${MIR}base.txz"  core-base  2013-09-27
        index_core freebsd-9.2 "${MIR}games.txz" core-games 2013-09-27
        index freebsd1 --sys freebsd-9.2 --arch i386 --mirror "${MIR}packages/"
        ;;
    9.3)
        MIR="${CMIRROR}i386/9.3-RELEASE/"
        PKG="${PMIRROR}FreeBSD:9:i386/release_3/"
        index_core freebsd-9.3 "${MIR}base.txz"  core-base  2014-07-20
        index_core freebsd-9.3 "${MIR}games.txz" core-games 2014-07-20
        index freebsd2 --sys freebsd-9.3 --mirror "$PKG"
        ;;
    10.0)
        MIR="${AMIRROR}i386/10.0-RELEASE/"
        PKG="${PMIRROR}FreeBSD:10:i386/release_0/"
        index_core freebsd-10.0 "${MIR}base.txz"  core-base  2014-01-20
        index_core freebsd-10.0 "${MIR}games.txz" core-games 2014-01-20
        index freebsd2 --sys freebsd-10.0 --mirror "$PKG"
        ;;
    10.1)
        MIR="${CMIRROR}i386/10.1-RELEASE/"
        PKG="${PMIRROR}FreeBSD:10:i386/release_1/"
        index_core freebsd-10.1 "${MIR}base.txz"  core-base  2014-11-14
        index_core freebsd-10.1 "${MIR}games.txz" core-games 2014-11-14
        index freebsd2 --sys freebsd-10.1 --mirror "$PKG"
        ;;
    10.2)
        MIR="${CMIRROR}i386/10.2-RELEASE/"
        PKG="${PMIRROR}FreeBSD:10:i386/release_2/"
        index_core freebsd-10.2 "${MIR}base.txz"  core-base  2015-08-13
        index_core freebsd-10.2 "${MIR}games.txz" core-games 2015-08-13
        index freebsd2 --sys freebsd-10.2 --mirror "$PKG"
        ;;
    10.3)
        MIR="${CMIRROR}i386/10.3-RELEASE/"
        PKG="${PMIRROR}FreeBSD:10:i386/release_3/"
        index_core freebsd-10.3 "${MIR}base.txz"  core-base  2016-04-04
        index_core freebsd-10.3 "${MIR}games.txz" core-games 2016-04-04
        index freebsd2 --sys freebsd-10.3 --mirror "$PKG"
        ;;
    11.0)
        MIR="${CMIRROR}i386/11.0-RELEASE/"
        PKG="${PMIRROR}FreeBSD:11:i386/release_0/"
        index_core freebsd-11.0 "${MIR}base.txz" core-base 2016-10-10
        index freebsd2 --sys freebsd-11.0 --mirror "$PKG"
        ;;
    11.1)
        MIR="${CMIRROR}amd64/11.1-RELEASE/"
        PKG="${PMIRROR}FreeBSD:11:amd64/release_1/"
        index_core freebsd-11.1 "${MIR}base.txz" core-base 2017-07-26
        index freebsd2 --sys freebsd-11.1 --mirror "$PKG"
        ;;
    old)
        $0 1.0
        $0 2.0.5
        $0 2.1.5
        $0 2.1.7
        $0 2.2.2
        $0 2.2.5
        $0 2.2.6
        $0 2.2.7
        $0 2.2.8
        $0 3.0
        $0 3.1
        $0 3.2
        $0 3.3
        $0 3.4
        $0 3.5
        $0 3.5.1
        $0 4.0
        $0 4.1
        $0 4.1.1
        $0 4.2
        $0 4.3
        $0 4.4
        $0 4.5
        $0 4.6
        $0 4.6.2
        $0 4.7
        $0 4.8
        $0 4.9
        $0 4.10
        $0 4.11
        $0 5.0
        $0 5.1
        $0 5.2
        $0 5.2.1
        $0 5.3
        $0 5.4
        $0 5.5
        $0 6.0
        $0 6.1
        $0 6.2
        $0 6.3
        $0 6.4
        $0 7.0
        $0 7.1
        $0 7.2
        $0 7.3
        $0 7.4
        $0 8.0
        $0 8.1
        $0 8.2
        $0 8.3
        $0 8.4
        $0 9.0
        $0 9.1
        $0 9.2
        $0 9.3
        $0 10.0
        $0 10.1
        $0 10.2
        $0 10.3
        $0 11.0
        $0 11.1
        ;;
esac
