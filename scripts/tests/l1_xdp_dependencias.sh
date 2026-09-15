#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -eu
base=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts/tests"
cp "$base/lib-xdp.sh" "$tmp/scripts/"
cp "$base/tests/l1_xdp.sh" "$base/tests/l1_xdp_bitmask.sh" "$tmp/scripts/tests/"
bash "$tmp/scripts/tests/l1_xdp.sh" > "$tmp/shell.txt"
rc=0
bash "$tmp/scripts/tests/l1_xdp_bitmask.sh" > "$tmp/bitmask.txt" || rc=$?
[ "$rc" -eq 77 ]
grep -q 'SKIP:' "$tmp/bitmask.txt"
echo 'PASS: shell executado; bitmask sem helper registrada como SKIP'
