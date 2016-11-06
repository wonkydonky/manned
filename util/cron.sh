#!/bin/bash

. ./common.sh

./index.sh daily
./deb.sh ubuntu_active
./deb.sh debian_active
echo "============ Updating SQL indices"
$PSQL -f update_indices.sql

