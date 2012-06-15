#!/bin/bash

# A fetcher for debian-style repositories.

CURL="curl -Ss"
PSQL="psql -U manned -Awtq"
TMP=`mktemp -d manned.deb.XXXXXX`


checkpkg() {
  SYSID=$1
  REPO=$2
  NAME=$3
  VERSION=$4
  SECTION=$5
  FILE=$6
  echo "===> $NAME-$VERSION"
  FN="$TMP/$NAME-$VERSION.deb"
  $CURL "$REPO/$FILE" -o "$FN" || return

  # Get the date from the last modification time of the debian-binary file
  # inside the .deb. Preferably, the date we store in the database indicates
  # when the *source* package has been uploaded, but this will work fine as
  # an approximation, I guess.
  DATE=`date -d "\`ar tv \"$FN\" debian-binary | perl -lne 's/^[^ ]+ [^ ]+ +\d+ (.+) debian-binary$/print $1/e'\`" "+%F"`

  # Insert package in the database
  PKGID=`echo "INSERT INTO package (system, category, name, version, released) VALUES(:'sysid',:'cat',:'name',:'ver',:'rel') RETURNING id"\
    | $PSQL -v "sysid=$SYSID" -v "cat=$SECTION" -v "name=$NAME" -v "ver=$VERSION" -v "rel=$DATE"`

  # Extract and handle the man pages
  if [ "$?" -eq 0 -a -n "$PKGID" ]; then
    ar p "$FN" data.tar.gz | ./add_tar.sh - $PKGID -z
  fi

  rm "$FN"
}


syncrepo() {
  SYSID=$1
  REPO=$2
  DISTRO=$3
  COMPONENTS=$4
  CONTENTSURL=${5:-"dists/$DISTRO/Contents-i386.gz"}
  echo "============ $REPO $DISTRO ($COMPONENTS)"

  # Get Contents.gz and Packages
  CFN="$TMP/Contents"
  PFN="$TMP/Packages"
  printf "" >"$PFN"
  $CURL "$REPO/$CONTENTSURL" -o "$CFN.gz" || return 1
  gunzip "$CFN.gz"

  for CMP in $COMPONENTS; do
    echo "MANDIFF-COMPONENT: $CMP" >>"$PFN"
    TFN="$TMP/Packages-$CMP.bz2"
    $CURL "$REPO/dists/$DISTRO/$CMP/binary-i386/Packages.bz2" -o "$TFN" || return 1
    bzcat "$TFN" >>"$PFN"
    rm "$TFN"
  done

  # Parse the Contents and Packages files and check with the database to figure
  # out which packages we need to download.
  mkfifo "$TMP/fifo"
  perl -l - $CFN $PFN $SYSID <<'EOP' >"$TMP/fifo" &
    ($cfn, $pfn, $sysid) = @ARGV;

    use DBI;
    $db = DBI->connect('dbi:Pg:dbname=manned', 'manned', '', {RaiseError => 1});

    open F, '<', $cfn or die $!;
    while(<F>) {
      chomp; @l=split/ +/;
      grep{ s{^.+/([^/]+)$}{$1}; $_ ne"-" and ($pkg{$_}=1) } split/,/, $l[1] if $l[0]=~/\/man\//
    }
    close F;

    open F, '<', $pfn or die $!;
    while(<F>) {
      chomp;
      $p = $1 if /^Package: (.+)/;
      $v = $1 if /^Version: (.+)/;
      $s = $1 if /^Section: (.+)/;
      $f = $1 if /^Filename: (.+)/;
      if(!$_) {
        if($p && $v && $s && $f) {
          print "$p $v $s $f" if $pkg{$p} && $pkg{$p} == 1
            && !$db->selectrow_arrayref(q{SELECT 1 FROM package WHERE system = ? AND name = ? AND version = ?}, {}, $sysid, $p, $v);
          warn "Duplicate package? $p\n" if $pkg{$p} && $pkg{$p} == 2;
          $pkg{$p} = 2;
        }
        $p=$v=$f=undef
      }
    }
    close F;
EOP

  while read l; do
    checkpkg $SYSID $REPO $l
  done <"$TMP/fifo"

  rm -f "$TMP/fifo" "$CFN" "$PFN"
}

# TODO: backports?

#syncrepo 2 "http://old-releases.ubuntu.com/ubuntu/" "warty" "main multiverse restricted universe"
#syncrepo 2 "http://old-releases.ubuntu.com/ubuntu/" "warty-updates" "main multiverse restricted universe" "dists/warty/Contents-i386.gz"
#syncrepo 2 "http://old-releases.ubuntu.com/ubuntu/" "warty-security" "main multiverse restricted universe" "dists/warty/Contents-i386.gz"

#syncrepo 3 "http://old-releases.ubuntu.com/ubuntu/" "hoary" "main multiverse restricted universe"
#syncrepo 3 "http://old-releases.ubuntu.com/ubuntu/" "hoary-updates" "main multiverse restricted universe" "dists/hoary/Contents-i386.gz"
#syncrepo 3 "http://old-releases.ubuntu.com/ubuntu/" "hoary-security" "main multiverse restricted universe" "dists/hoary/Contents-i386.gz"

#syncrepo 4 "http://old-releases.ubuntu.com/ubuntu/" "breezy" "main multiverse restricted universe"
#syncrepo 4 "http://old-releases.ubuntu.com/ubuntu/" "breezy-updates" "main multiverse restricted universe" "dists/breezy/Contents-i386.gz"
#syncrepo 4 "http://old-releases.ubuntu.com/ubuntu/" "breezy-security" "main multiverse restricted universe" "dists/breezy/Contents-i386.gz"

rm -rf "$TMP"

