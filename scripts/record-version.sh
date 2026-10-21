#!/bin/sh
# Usage: record-version <tool> <repo> <out-root> [patch-dir...]
#
# Run from the tool's source checkout. Records the commit it was built from
# (plus any srcKit patches applied) in
# <out-root>/usr/local/share/srckit/versions.d/<tool>.
set -eu

tool=$1
repo=$2
out=$3
shift 3

patches=$(
    for d in "$@"; do
        for p in "$d"/*.patch; do
            if [ -e "$p" ]; then basename "$p"; fi
        done
    done | tr '\n' ' '
)
patches=${patches% }

mkdir -p "$out/usr/local/share/srckit/versions.d"
printf '%-9s %s  %s%s\n' "$tool" "$(git rev-parse HEAD)" "$repo" \
    "${patches:+  patches: $patches}" \
    > "$out/usr/local/share/srckit/versions.d/$tool"
