#!/bin/bash

# Usage: ./arch.sh
# Synchronises the database with an Arch mirror, fetching any packages that
# aren't yet in the database and may have man pages.

MIRROR=http://ftp.nluug.nl/pub/os/Linux/distr/archlinux
REPOS="core extra community"
DEBUG=false
SYSID=1

. ./common.sh


checkpkg() {
  REPO=$1
  FN=$2
  D="$TMP/$REPO/$FN"
  if [ ! \( -d "$D" -a -f "$D/files" -a -f "$D/desc" \) ]; then
    echo "===> $FN"
    echo "Invalid item, ignoring"
    return
  fi
  grep -q /man/ "$D/files"
  if [ "$?" -ne 0 ]; then
    $DEBUG && echo "===> $FN"
    $DEBUG && echo "No mans"
    return
  fi

  # Somewhat inefficient description parsing
  FILENAME=`grep -A 1 '%FILENAME%' "$D/desc" | tail -n 1`
  NAME=`grep -A 1 '%NAME%' "$D/desc" | tail -n 1`
  VERSION=`grep -A 1 '%VERSION%' "$D/desc" | tail -n 1`
  BUILDDATE=`grep -A 1 '%BUILDDATE%' "$D/desc" | tail -n 1`
  if [ -z "$FILENAME" -o -z "$NAME" -o -z "$VERSION" -o -z "$BUILDDATE" ]; then
    echo "===> $FN"
    echo "Invalid/missing description info"
    return
  fi
  BUILDDATE=`date -d "@$BUILDDATE" '+%F'`

  add_pkginfo $SYSID "$REPO" "$NAME" "$VERSION" "$BUILDDATE"
  if [ "$?" -eq 0 ]; then
    $DEBUG && echo "===> $FN"
    $DEBUG && echo "Already up-to-date"
    return
  fi

  echo "===> $FN"
  F="$TMP/$REPO/$FILENAME"
  $CURL "$MIRROR/$REPO/os/i686/$FILENAME" -o "$F" || return
  add_tar "$F" "$PKGID"
  rm -f "$F"
}


syncrepo() {
  REPO=$1
  F="$TMP/$REPO/repo.tar.gz"
  echo "============ $MIRROR $REPO"
  $CURL "$MIRROR/$REPO/os/i686/$REPO.files.tar.gz" -o "$F" || return 1
  tar -C "$TMP/$REPO" -xf "$F" || return 1
  rm -f "$F"
  for fn in "$TMP/$REPO"/*; do
    checkpkg "$REPO" `basename "$fn"`
  done
}


for r in $REPOS; do
  mkdir "$TMP/$r"
  syncrepo $r
  rm -rf "$TMP/$r"
done

