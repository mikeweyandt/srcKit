#!/usr/bin/env bash
# Smoke test for the srcKit image: runs srcml, srcslice and srcdiff on the
# fixtures and compares their output with the known-good files in expected/.
#
#   tests/run.sh            compare; exits 1 if anything differs
#   tests/run.sh --update   rewrite expected/ from the current tools
#
# After bumping an upstream ref: rebuild, run with --update, review
# `git diff tests/expected`, and commit.
set -euo pipefail

update=0
case "${1:-}" in
    --update) update=1 ;;
    "") ;;
    *) echo "usage: $0 [--update]" >&2; exit 2 ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
expected=$here/expected
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

fail() {
    echo "FAIL $*"
    failures=$((failures + 1))
}

# check <name> <command...>
# Runs the command and compares its stdout with expected/<name>. Output on
# stderr also fails the check: srcdiff reports errors there but exits 0.
check() {
    local name=$1
    shift
    if ! "$@" > "$tmp/$name" 2> "$tmp/$name.err"; then
        fail "$name: command exited non-zero"
        cat "$tmp/$name.err"
        return
    fi
    if [[ -s $tmp/$name.err ]]; then
        fail "$name: unexpected stderr"
        cat "$tmp/$name.err"
        return
    fi
    if ((update)); then
        cp "$tmp/$name" "$expected/$name"
        echo "updated $name"
    elif diff -u --label "expected/$name" --label "actual/$name" \
            "$expected/$name" "$tmp/$name"; then
        echo "ok   $name"
    else
        fail "$name: output differs from expected/$name"
    fi
}

# srcSlice needs srcML with positions and hashes, and prints status lines
# to stdout when writing to a file. (Chained with && because `set -e` is
# suspended inside check's `if`.)
slice() {
    srcml --position --hash "$1" -o "$tmp/slice.xml" \
        && srcslice "$tmp/slice.xml" -o "$tmp/slice.json" > /dev/null \
        && jq -S . "$tmp/slice.json"
}

if [[ -r /usr/local/share/srckit/versions ]]; then
    cat /usr/local/share/srckit/versions
fi

for tool in srcml srcslice srcdiff; do
    if ! path=$(command -v "$tool"); then
        fail "$tool: not on PATH"
    elif ldd "$path" | grep 'not found'; then
        fail "$tool: missing shared libraries"
    fi
done
srcml --version > /dev/null || fail "srcml --version"
srcdiff --version > /dev/null || fail "srcdiff --version"
srcslice --help > /dev/null || fail "srcslice --help"

# Run from fixtures/ so filename attributes are stable relative paths.
cd "$here/fixtures"
check srcml.xml           srcml v1/example.cpp
check srcslice.json       slice v1/example.cpp
check srcdiff.xml         srcdiff v1/example.cpp v2/example.cpp
check srcdiff-unified.txt srcdiff -u v1/example.cpp v2/example.cpp

if ((failures)); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
