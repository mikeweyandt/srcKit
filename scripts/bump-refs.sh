#!/usr/bin/env bash
# Usage: scripts/bump-refs.sh [srcml|srcslice|srcdiff ...]
#
# Re-pins *_REF in the Dockerfile to the current head of each tool's branch
# (develop by default; e.g. SRCSLICE_BRANCH=main to follow another branch).
# With no arguments, bumps all three. Then rebuild, run
# `tests/run.sh --update`, review the diffs, and commit.
set -euo pipefail

cd "$(dirname "$0")/.."

if (($# == 0)); then
    set -- srcml srcslice srcdiff
fi

for tool in "$@"; do
    var=$(tr '[:lower:]' '[:upper:]' <<< "$tool")
    branch_var=${var}_BRANCH
    branch=${!branch_var:-develop}

    repo=$(sed -n "s/^ARG ${var}_REPO=//p" Dockerfile)
    old=$(sed -n "s/^ARG ${var}_REF=//p" Dockerfile)
    if [[ -z $repo || -z $old ]]; then
        echo "unknown tool: $tool" >&2
        exit 2
    fi

    new=$(git ls-remote --exit-code "$repo" "refs/heads/$branch" | cut -f1)
    sed -i.bak "s/^ARG ${var}_REF=.*/ARG ${var}_REF=$new/" Dockerfile
    rm Dockerfile.bak

    if [[ $old == "$new" ]]; then
        echo "$tool: unchanged ($branch @ $new)"
    else
        echo "$tool: $old -> $new ($branch)"
        echo "    ${repo%.git}/compare/$old...$new"
    fi
done
