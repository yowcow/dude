#!/usr/bin/env bash
# Throwaway probe for yowcow/dude#591 — do not merge.
set -eu
greet() {
  local name=$1
  echo "hello $name"
}
total=0
for n in 1 2 3; do
  total=$((total + n))
done
greet "$total"
rm -rf $TMPDIR/probe-$1
cat $2 | grep foo > out.txt
