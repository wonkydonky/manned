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


check_pkg() { # <sysid> <base-url> <category> <filename> <name> <version>
  SYSID=$1
  URL=$2
  CAT=$3
  FN=$4
  NAME=$5
  VER=$6
  echo "===> $NAME $VER"
  $CURL "$URL/$CAT/$FN" -o "$TMP/$FN" || return 1

  DATE=`tar -tvf "$TMP/$FN" '+DESC' | perl -lne 's/.+ ([^ ]+) [^ ]+ \+DESC$/print $1/e'`
  if [ -z "$DATE" ]; then
    echo "Error: No date found for +DESC"
    rm -f "$TMP/$FN"
    return
  fi

  PKGID=`echo "INSERT INTO package (system, category, name, version, released) VALUES(:'sysid',:'cat',:'name',:'ver',:'rel') RETURNING id"\
    | $PSQL -v "sysid=$SYSID" -v "cat=$CAT" -v "name=$NAME" -v "ver=$VER" -v "rel=$DATE"`
  add_tar "$TMP/$FN" $PKGID
  rm -f "$TMP/$FN"
}


# Will check and index a packages/ directory. Uses the 'Latest/' directory as a
# hint to split the package name from its version, and the other directories
# (except All/) to find the actual packages and their category. Date of the
# packages is extracted from the last modification time of the '+DESC' file in
# each tarball.
# TODO: Handle .tbz
check_pkgdir() { # <sysid> <url>
  SYSID=$1
  URL=$2
  # Get the list of categories from the lighttpd directory index.
  $CURL "$URL/" | perl -lne 'm{href="([a-z0-9-]+)/">\1</a>/} && print $1' >"$TMP/categories"
  # Get the list of package names without version string.
  $CURL "$URL/Latest/" | perl -lne 'm{href="([^ "]+)\.tgz">\1\.tgz</a>} && print $1' >"$TMP/pkgnames"
  if [ \( ! -s "$TMP/categories" \) -o \( ! -s "$TMP/pkgnames" \) ]; then
    echo "== Error fetching package names or directory index."
    rm -f "$TMP/categories" "$TMP/pkgnames"
    return
  fi

  # Now check each category directory
  while read CAT; do
    $CURL "$URL/$CAT/" | perl -lne 'm{href="([^ "]+)\.tgz">\1\.tgz</a>} && print $1' >"$TMP/pkglist"
    if [ ! -s "$TMP/pkglist" ]; then
      echo "== Error fetching package index for /$CAT/"
      continue
    fi
    perl -l - "$TMP/pkgnames" "$TMP/pkglist" $SYSID <<'EOP' >"$TMP/newpkgs"
      ($names, $list, $sysid) = @ARGV;

      use DBI;
      $db = DBI->connect('dbi:Pg:dbname=manned', 'manned', '', {RaiseError => 1});

      open F, '<', $names or die $!;
      %names = map { chomp; ($_,1) } <F>;
      close F;

      open F, '<', $list or die $!;
      while(<F>) {
        chomp;
        ($v,$n)=('',$_);
        $v = $v ? "$1-$v" : $1 while(!$names{$_} && s/-([^-]+)$//);
        warn "== Unknown package: $n\n" if !$_ || !$names{$_};
        print "$n.tgz $_ $v" if $v && $_ && $names{$_}
          && !$db->selectrow_arrayref(q{SELECT 1 FROM package WHERE system = ? AND name = ? AND version = ?}, {}, $sysid, $_, $v);
      }
      close F;
EOP

    while read NFO; do
      check_pkg $SYSID $URL $CAT $NFO
    done <"$TMP/newpkgs"

    rm -f "$TMP/pkglist" "$TMP/newpkgs"
  done <"$TMP/categories"

  rm -f "$TMP/categories" "$TMP/pkgnames"
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

f2_2_8() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/2.2.8-RELEASE"
  echo "============ $MIR"
  check_dist 37 "$MIR/des/des." "core-des-des" "1998-11-29" ab
  check_dist 37 "$MIR/des/krb." "core-des-krb" "1998-11-29" ad
  check_dist 37 "$MIR/manpages/manpages." "core-manpages" "1998-11-29" ax
  check_dist 37 "$MIR/XF86333/Xfsrv.tgz" "core-XF86333-Xfsrv" "1998-11-14"
  check_dist 37 "$MIR/XF86333/Xman.tgz" "core-XF86333-Xman" "1998-11-14"
  check_dist 37 "$MIR/XF86333/Xset.tgz" "core-XF86333-Xset" "1998-11-14"
  check_pkgdir 37 "$MIR/packages"
}

f3_0() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.0-RELEASE"
  echo "============ $MIR"
  check_dist 38 "$MIR/des/des." "core-des-des" "1998-10-16" ab
  check_dist 38 "$MIR/des/krb." "core-des-krb" "1998-10-16" ae
  check_dist 38 "$MIR/manpages/manpages." "core-manpages" "1998-10-16" bb
  check_dist 38 "$MIR/XF86332/Xfsrv.tgz" "core-XF86332-Xfsrv" "1998-09-28"
  check_dist 38 "$MIR/XF86332/Xman.tgz" "core-XF86332-Xman" "1998-09-28"
  check_dist 38 "$MIR/XF86332/Xset.tgz" "core-XF86332-Xset" "1998-09-28"
}

f3_1() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.1-RELEASE"
  echo "============ $MIR"
  check_dist 39 "$MIR/des/des." "core-des-des" "1999-02-15" ab
  check_dist 39 "$MIR/des/krb." "core-des-krb" "1999-02-15" ae
  check_dist 39 "$MIR/manpages/manpages." "core-manpages" "1999-02-15" be
  check_dist 39 "$MIR/XF86332/Xfsrv.tgz" "core-XF86332-Xfsrv" "1998-09-28"
  check_dist 39 "$MIR/XF86332/Xman.tgz" "core-XF86332-Xman" "1998-09-28"
  check_dist 39 "$MIR/XF86332/Xset.tgz" "core-XF86332-Xset" "1998-09-28"
}

f3_2() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.2-RELEASE"
  echo "============ $MIR"
  check_dist 40 "$MIR/des/des." "core-des-des" "1999-05-18" ab
  check_dist 40 "$MIR/des/krb." "core-des-krb" "1999-05-18" ae
  check_dist 40 "$MIR/manpages/manpages." "core-manpages" "1999-05-18" be
  check_dist 40 "$MIR/XF86333/Xfsrv.tgz" "core-XF86333-Xfsrv" "1998-11-14"
  check_dist 40 "$MIR/XF86333/Xman.tgz" "core-XF86333-Xman" "1998-11-14"
  check_dist 40 "$MIR/XF86333/Xset.tgz" "core-XF86333-Xset" "1998-11-14"
}

f3_3() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.3-RELEASE"
  echo "============ $MIR"
  check_dist 41 "$MIR/des/des." "core-des-des" "1999-09-17" ab
  check_dist 41 "$MIR/des/krb." "core-des-krb" "1999-09-17" ae
  check_dist 41 "$MIR/manpages/manpages." "core-manpages" "1999-09-17" au
  check_dist 41 "$MIR/XF86335/Xfsrv.tgz" "core-XF86335-Xfsrv" "1999-08-31"
  check_dist 41 "$MIR/XF86335/Xman.tgz" "core-XF86335-Xman" "1999-08-31"
  check_dist 41 "$MIR/XF86335/Xset.tgz" "core-XF86335-Xset" "1999-08-31"
}

f3_4() {
  MIR="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/old-releases/i386/3.4-RELEASE"
  echo "============ $MIR"
  check_dist 42 "$MIR/des/des." "core-des-des" "1999-12-20" ac
  check_dist 42 "$MIR/des/krb." "core-des-krb" "1999-12-20" ae
  check_dist 42 "$MIR/manpages/manpages." "core-manpages" "1999-12-20" av
  check_dist 42 "$MIR/XF86335/Xfsrv.tgz" "core-XF86335-Xfsrv" "1999-08-31"
  check_dist 42 "$MIR/XF86335/Xman.tgz" "core-XF86335-Xman" "1999-08-31"
  check_dist 42 "$MIR/XF86335/Xset.tgz" "core-XF86335-Xset" "1999-08-31"
  check_pkgdir 42 "$MIR/packages"
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
  f2_2_8
  f3_0
  f3_1
  f3_2
  f3_3
  f3_4
}

"$@"
