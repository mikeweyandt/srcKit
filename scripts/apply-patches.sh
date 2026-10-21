#!/bin/sh
# Usage: apply-patches <patch-dir> <src-dir>
#
# Applies <patch-dir>/*.patch to <src-dir> in name order. A patch that no
# longer applies cleanly (or is already applied upstream) fails the build:
# update or delete it.
set -eu

patch_dir=$1
src_dir=$2

for p in "$patch_dir"/*.patch; do
    [ -e "$p" ] || continue
    echo ">> applying $(basename "$p") to $src_dir"
    patch -d "$src_dir" -p1 --forward --fuzz=0 --no-backup-if-mismatch -i "$p"
done
