#!/bin/sh

. ./common.sh


add_splittar() { # <url-prefix> <last-sequence> <pkgid> <flags>
  $CURL "$1{"`perl -le "print join ',', 'aa'..'$2'"`'}' | add_tar - $3 $4
}


# Check whether we already have a core file in the DB, otherwise add it.
# (The version we use for the core file is the same as its date)
# If <last-sequence> is set, add_splittar() is used. Otherwise the file is
# assumed to be a regular tar.gz.
check_dist() { # <sysid> <url-prefix> <pkgname> <date> <last-sequence>
  add_pkginfo $1 core "$3" "$4" "$4" && return
  echo "===> $3"
  if [ -n "$5" ]; then
    add_splittar "$2" "$5" $PKGID -z
  else
    $CURL "$2" | add_tar - $PKGID -z
  fi
}


# Adds a FreeBSD 1.0 package. These lack version information and categories and
# are in general not as well organized the package repositories in the later
# versions.
check_oldpkg() { # <sysid> <url> <pkgname> <date>
  add_pkginfo $1 "packages" "$3" "$4" "$4" && return
  echo "===> $3"
  $CURL "$2" | add_tar - $PKGID -z
}


f1_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/1.0-RELEASE"
  echo "============ $MIR"
  # Core distribution
  check_dist 29 "$MIR/tarballs/bindist/bin_tgz." "core-bindist" "1993-11-15" dc
  check_dist 29 "$MIR/tarballs/xfree86/doc.tgz" "core-xfree86-doc" "1993-10-25"
  check_dist 29 "$MIR/tarballs/xfree86/fontserv.tgz" "core-xfree86-fontserv" "1993-10-21"
  check_dist 29 "$MIR/tarballs/xfree86/man.tgz" "core-xfree86-man" "1993-10-20"
  check_dist 29 "$MIR/tarballs/xfree86/pex.tgz" "core-xfree86-pex" "1993-10-21"
  # A few packages
  check_oldpkg 29 "$MIR/packages/emacs-19-19_bin.tgz" "emacs-19-19_bin" "1993-09-13"
  check_oldpkg 29 "$MIR/packages/f2c_bin.tgz" "f2c_bin" "1993-10-01"
  check_oldpkg 29 "$MIR/packages/fileutils_bin.tgz" "fileutils_bin" "1993-10-06"
  check_oldpkg 29 "$MIR/packages/ghostscript_bin.tgz" "ghostscript_bin" "1993-10-02"
  check_oldpkg 29 "$MIR/packages/gopher_bin.tgz" "gopher_bin" "1993-10-15"
  check_oldpkg 29 "$MIR/packages/info-zip_bin.tgz" "info-zip_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/jpeg_bin.tgz" "jpeg_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/kermit_bin.tgz" "kermit_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/ksh_bin.tgz" "ksh_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/miscutils_bin.tgz" "miscutils_bin" "1993-09-06"
  check_oldpkg 29 "$MIR/packages/mtools_bin.tgz" "mtools_bin" "1993-08-30"
  check_oldpkg 29 "$MIR/packages/pbmplus_bin.tgz" "pbmplus_bin" "1993-10-05"
  check_oldpkg 29 "$MIR/packages/pkg_install.tar.gz" "pkg_install" "1993-10-10"
  check_oldpkg 29 "$MIR/packages/shellutils_bin.tgz" "shellutils_bin" "1993-10-06"
  check_oldpkg 29 "$MIR/packages/tcl_bin.tgz" "tcl_bin" "1993-09-18"
  check_oldpkg 29 "$MIR/packages/tcsh_bin.tgz" "tcsh_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/textutils_bin.tgz" "textutils_bin" "1993-09-05"
  check_oldpkg 29 "$MIR/packages/tk_bin.tgz" "tk_bin" "1993-09-18"
  check_oldpkg 29 "$MIR/packages/urt_bin.tgz" "urt_bin" "1993-10-05"
  check_oldpkg 29 "$MIR/packages/xlock_bin.tgz" "xlock_bin" "1993-09-04"
  check_oldpkg 29 "$MIR/packages/xv_bin.tgz" "xv_bin" "1993-09-06"
  check_oldpkg 29 "$MIR/packages/xview32b.tgz" "xview32b" "1993-09-16"
  check_oldpkg 29 "$MIR/packages/zsh_bin.tgz" "zsh_bin" "1993-09-04"
}

f2_0_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.0.5-RELEASE"
  echo "============ $MIR"
  check_dist 30 "$MIR/des/des.aa" "core-des-des" "1995-06-11"
  check_dist 30 "$MIR/des/krb." "core-des-krb" "1995-06-11" ac
  check_dist 30 "$MIR/manpages/manpages." "core-manpages" "1995-06-09" al
}

f2_1_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.1.5-RELEASE"
  echo "============ $MIR"
  check_dist 31 "$MIR/des/des.aa" "core-des-des" "1996-07-16"
  check_dist 31 "$MIR/des/krb." "core-des-krb" "1996-07-16" ac
  check_dist 31 "$MIR/manpages/manpages." "core-manpages" "1996-07-16" am
}

f2_1_7() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.1.7-RELEASE"
  echo "============ $MIR"
  check_dist 32 "$MIR/des/des.aa" "core-des-des" "1997-02-19"
  check_dist 32 "$MIR/des/krb." "core-des-krb" "1997-02-19" ac
  check_dist 32 "$MIR/manpages/manpages." "core-manpages" "1997-02-19" am
}

f2_2_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.2-RELEASE"
  echo "============ $MIR"
  check_dist 33 "$MIR/des/des." "core-des-des" "1997-05-20" ab
  check_dist 33 "$MIR/des/krb." "core-des-krb" "1997-05-20" ac
  check_dist 33 "$MIR/manpages/manpages." "core-manpages" "1997-05-20" ap
}

f2_2_5() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.5-RELEASE"
  echo "============ $MIR"
  check_dist 34 "$MIR/des/des." "core-des-des" "1997-10-22" ab
  check_dist 34 "$MIR/des/krb." "core-des-krb" "1997-10-22" ad
  check_dist 34 "$MIR/manpages/manpages." "core-manpages" "1997-10-22" an
}

f2_2_6() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.6-RELEASE"
  echo "============ $MIR"
  check_dist 35 "$MIR/des/des." "core-des-des" "1998-03-25" ab
  check_dist 35 "$MIR/des/krb." "core-des-krb" "1998-03-25" ad
  check_dist 35 "$MIR/manpages/manpages." "core-manpages" "1998-03-25" ao
}

f2_2_7() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.7-RELEASE"
  echo "============ $MIR"
  check_dist 36 "$MIR/des/des." "core-des-des" "1998-07-22" ab
  check_dist 36 "$MIR/des/krb." "core-des-krb" "1998-07-22" ad
  check_dist 36 "$MIR/manpages/manpages." "core-manpages" "1998-07-22" ao
  check_dist 36 "$MIR/XF86332/X332fsrv.tgz" "core-XF86332-X332fsrv" "1998-03-01"
  check_dist 36 "$MIR/XF86332/X332man.tgz" "core-XF86332-X332man" "1998-03-01"
  check_dist 36 "$MIR/XF86332/X332set.tgz" "core-XF86332-X332set" "1998-03-01"
}


old() {
  f1_0
  f2_0_5
  f2_1_5
  f2_1_7
  f2_2_2
  f2_2_5
  f2_2_6
  f2_2_7
}

"$@"
