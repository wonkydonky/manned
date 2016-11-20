#!/bin/bash

. ./common.sh

./arch.sh active
./debian.sh active

echo "============ Updating SQL indices"
$PSQL -f update_indices.sql
