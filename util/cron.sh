#!/bin/sh

PSQL="psql -U manned -Awtq"

./arch.sh
./deb.sh ubuntu_active
./deb.sh debian_active
echo "============ Updating SQL indices"
$PGSL -f update_indices.sql

