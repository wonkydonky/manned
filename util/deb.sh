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
  $CURL "$REPO$FILE" -o "$FN" || return

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
    DATAFN=`ar t $FN | grep -F data.tar`
    case "$DATAFN" in
      "data.tar.gz") DATAZ="-z" ;;
      "data.tar.bz2") DATAZ="-j" ;;
      "data.tar.lzma") DATAZ="--lzma" ;;
      "data.tar.xz") DATAZ="-J" ;;
      *) echo "No data.tar found, or unknown compression format."; DATAZ="ERR" ;;
    esac

    [ "$DATAZ" != "ERR" ] && ar p "$FN" "$DATAFN" | ./add_tar.sh - $PKGID $DATAZ
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
  if [ "$CONTENTSURL" != "-" ]; then
    $CURL "$REPO$CONTENTSURL" -o "$CFN.gz" || return 1
    gunzip "$CFN.gz"
  fi

  for CMP in $COMPONENTS; do
    echo "MANDIFF-COMPONENT: $CMP" >>"$PFN"
    TFN="$TMP/Packages-$CMP.bz2"
    $CURL "${REPO}dists/$DISTRO/$CMP/binary-i386/Packages.bz2" -o "$TFN" || return 1
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
          #warn "Duplicate package? $p\n" if $pkg{$p} && $pkg{$p} == 2;
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

ubuntu_warty() {
  syncrepo 2 "http://old-releases.ubuntu.com/ubuntu/" "warty" "main multiverse restricted universe"
  syncrepo 2 "http://old-releases.ubuntu.com/ubuntu/" "warty-updates" "main multiverse restricted universe" "dists/warty/Contents-i386.gz"
  syncrepo 2 "http://old-releases.ubuntu.com/ubuntu/" "warty-security" "main multiverse restricted universe" "dists/warty/Contents-i386.gz"
}

ubuntu_hoary() {
  syncrepo 3 "http://old-releases.ubuntu.com/ubuntu/" "hoary" "main multiverse restricted universe"
  syncrepo 3 "http://old-releases.ubuntu.com/ubuntu/" "hoary-updates" "main multiverse restricted universe" "dists/hoary/Contents-i386.gz"
  syncrepo 3 "http://old-releases.ubuntu.com/ubuntu/" "hoary-security" "main multiverse restricted universe" "dists/hoary/Contents-i386.gz"
}

ubuntu_breezy() {
  syncrepo 4 "http://old-releases.ubuntu.com/ubuntu/" "breezy" "main multiverse restricted universe"
  syncrepo 4 "http://old-releases.ubuntu.com/ubuntu/" "breezy-updates" "main multiverse restricted universe" "dists/breezy/Contents-i386.gz"
  syncrepo 4 "http://old-releases.ubuntu.com/ubuntu/" "breezy-security" "main multiverse restricted universe" "dists/breezy/Contents-i386.gz"
}

ubuntu_dapper() {
  # Contents-i386.gz in dists/dapper/ is broken, so try to combine the files from breezy, edgy and Contents-hppa.gz.
  $CURL "http://old-releases.ubuntu.com/ubuntu/dists/dapper/Contents-hppa.gz" -o "$TMP/Contents-TMP.gz" || return
  zcat "$TMP/Contents-TMP.gz" > "$TMP/Contents"
  rm "$TMP/Contents-TMP.gz"
  $CURL "http://old-releases.ubuntu.com/ubuntu/dists/breezy/Contents-i386.gz" -o "$TMP/Contents-TMP.gz" || return
  zcat "$TMP/Contents-TMP.gz" >> "$TMP/Contents"
  rm "$TMP/Contents-TMP.gz"
  $CURL "http://old-releases.ubuntu.com/ubuntu/dists/edgy/Contents-i386.gz" -o "$TMP/Contents-TMP.gz" || return
  zcat "$TMP/Contents-TMP.gz" >> "$TMP/Contents"
  rm "$TMP/Contents-TMP.gz"
  syncrepo 5 "http://old-releases.ubuntu.com/ubuntu/" "dapper" "main multiverse restricted universe" -

  # -updates and -security do have a functional Contents-i386.gz
  syncrepo 5 "http://old-releases.ubuntu.com/ubuntu/" "dapper-updates" "main multiverse restricted universe"
  syncrepo 5 "http://old-releases.ubuntu.com/ubuntu/" "dapper-security" "main multiverse restricted universe"
}

ubuntu_edgy() {
  syncrepo 6 "http://old-releases.ubuntu.com/ubuntu/" "edgy" "main multiverse restricted universe"
  syncrepo 6 "http://old-releases.ubuntu.com/ubuntu/" "edgy-updates" "main multiverse restricted universe" "dists/edgy/Contents-i386.gz"
  syncrepo 6 "http://old-releases.ubuntu.com/ubuntu/" "edgy-security" "main multiverse restricted universe" "dists/edgy/Contents-i386.gz"
}

ubuntu_feisty() {
  syncrepo 7 "http://old-releases.ubuntu.com/ubuntu/" "feisty" "main multiverse restricted universe"
  syncrepo 7 "http://old-releases.ubuntu.com/ubuntu/" "feisty-updates" "main multiverse restricted universe"
  syncrepo 7 "http://old-releases.ubuntu.com/ubuntu/" "feisty-security" "main multiverse restricted universe"
}

ubuntu_gutsy() {
  syncrepo 8 "http://old-releases.ubuntu.com/ubuntu/" "gutsy" "main multiverse restricted universe"
  syncrepo 8 "http://old-releases.ubuntu.com/ubuntu/" "gutsy-updates" "main multiverse restricted universe"
  syncrepo 8 "http://old-releases.ubuntu.com/ubuntu/" "gutsy-security" "main multiverse restricted universe"
}

ubuntu_hardy() {
  syncrepo 9 "http://nl.archive.ubuntu.com/ubuntu/" "hardy" "main multiverse restricted universe"
  syncrepo 9 "http://nl.archive.ubuntu.com/ubuntu/" "hardy-updates" "main multiverse restricted universe"
  syncrepo 9 "http://nl.archive.ubuntu.com/ubuntu/" "hardy-security" "main multiverse restricted universe"
}

ubuntu_intrepid() {
  syncrepo 10 "http://old-releases.ubuntu.com/ubuntu/" "intrepid" "main multiverse restricted universe"
  syncrepo 10 "http://old-releases.ubuntu.com/ubuntu/" "intrepid-updates" "main multiverse restricted universe"
  syncrepo 10 "http://old-releases.ubuntu.com/ubuntu/" "intrepid-security" "main multiverse restricted universe"
}

ubuntu_jaunty() {
  syncrepo 11 "http://old-releases.ubuntu.com/ubuntu/" "jaunty" "main multiverse restricted universe"
  syncrepo 11 "http://old-releases.ubuntu.com/ubuntu/" "jaunty-updates" "main multiverse restricted universe"
  syncrepo 11 "http://old-releases.ubuntu.com/ubuntu/" "jaunty-security" "main multiverse restricted universe"
}

ubuntu_karmic() {
  syncrepo 12 "http://old-releases.ubuntu.com/ubuntu/" "karmic" "main multiverse restricted universe"
  syncrepo 12 "http://old-releases.ubuntu.com/ubuntu/" "karmic-updates" "main multiverse restricted universe"
  syncrepo 12 "http://old-releases.ubuntu.com/ubuntu/" "karmic-security" "main multiverse restricted universe"
}

ubuntu_lucid() {
  syncrepo 13 "http://nl.archive.ubuntu.com/ubuntu/" "lucid" "main multiverse restricted universe"
  syncrepo 13 "http://nl.archive.ubuntu.com/ubuntu/" "lucid-updates" "main multiverse restricted universe"
  syncrepo 13 "http://nl.archive.ubuntu.com/ubuntu/" "lucid-security" "main multiverse restricted universe"
}

ubuntu_maverick() {
  syncrepo 14 "http://nl.archive.ubuntu.com/ubuntu/" "maverick" "main multiverse restricted universe"
  syncrepo 14 "http://nl.archive.ubuntu.com/ubuntu/" "maverick-updates" "main multiverse restricted universe"
  syncrepo 14 "http://nl.archive.ubuntu.com/ubuntu/" "maverick-security" "main multiverse restricted universe"
}

ubuntu_natty() {
  syncrepo 15 "http://nl.archive.ubuntu.com/ubuntu/" "natty" "main multiverse restricted universe"
  syncrepo 15 "http://nl.archive.ubuntu.com/ubuntu/" "natty-updates" "main multiverse restricted universe"
  syncrepo 15 "http://nl.archive.ubuntu.com/ubuntu/" "natty-security" "main multiverse restricted universe"
}

ubuntu_oneiric() {
  syncrepo 16 "http://nl.archive.ubuntu.com/ubuntu/" "oneiric" "main multiverse restricted universe"
  syncrepo 16 "http://nl.archive.ubuntu.com/ubuntu/" "oneiric-updates" "main multiverse restricted universe"
  syncrepo 16 "http://nl.archive.ubuntu.com/ubuntu/" "oneiric-security" "main multiverse restricted universe"
}

ubuntu_precise() {
  syncrepo 17 "http://nl.archive.ubuntu.com/ubuntu/" "precise" "main multiverse restricted universe"
  syncrepo 17 "http://nl.archive.ubuntu.com/ubuntu/" "precise-updates" "main multiverse restricted universe"
  syncrepo 17 "http://nl.archive.ubuntu.com/ubuntu/" "precise-security" "main multiverse restricted universe"
}

ubuntu_old() {
  ubuntu_warty
  ubuntu_hoary
  ubuntu_breezy
  ubuntu_dapper
  ubuntu_edgy
  ubuntu_feisty
  ubuntu_gutsy
  ubuntu_intrepid
  ubuntu_jaunty
  ubuntu_karmic
  ubuntu_maverick
}

ubuntu_active() {
  ubuntu_hardy    # until 2013-04
  ubuntu_lucid    # until 2015-04
  ubuntu_natty    # until 2012-10
  ubuntu_oneiric  # until 2013-04
  ubuntu_precise  # until 2017-04
}


"$@"

rm -rf "$TMP"

