#!/bin/sh

PSQL="psql -U manned -Awtq"


./arch.sh current
./debian.sh current
./centos.sh current
./fedora.sh current
./ubuntu.sh current

echo "============ Updating SQL indices"
$PSQL -f update_indices.sql
