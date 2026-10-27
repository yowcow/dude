#!/usr/bin/env bash
# The word-limit gate: every skills/*/SKILL.md and skills/*/references/*.md must
# be listed in tests/word-limits.txt and stay within its listed word cap.
# Usage: word-limits.sh [<repo-root>]
#
# Why this exists: without a cap the prose re-inflates after each trim and
# nobody observes it (#760). Caps start at the current count and only go down;
# a raise is a visible line in the PR diff.
#
# Words are counted with awk's field splitting, not `wc -w`: under the C locale
# GNU `wc` drops tokens made only of non-ASCII bytes and BSD `wc` does not, so
# caps seeded from `wc` would break on another machine.
#
# The root is anchored on this file's own location, never the cwd; the optional
# argument lets tests/word-limits_test.sh point the gate at a synthetic tree.
# That test's first case runs this against the real tree, which is how `make
# test` runs it with no Makefile or workflow change.
#
# `set -e` is deliberately absent: this is an accumulating reporter, and one
# problem must not stop it from naming the rest.
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(CDPATH='' cd -- "${HERE}/.." && pwd)"
fi
LIST="${ROOT}/tests/word-limits.txt"

if [ ! -f "$LIST" ] || [ ! -r "$LIST" ]; then
  printf 'word-limits: cannot read %s\n' "$LIST" >&2
  exit 1
fi

errors=0
err() {
  printf 'word-limits: %s\n' "$*" >&2
  errors=$((errors + 1))
}

# Tab-separated "<path> <count>" and "<path> <limit>" lines.
FOUND=""
LISTED=""

# An unmatched glob stays literal, and the -f test drops it.
for f in "$ROOT"/skills/*/SKILL.md "$ROOT"/skills/*/references/*.md; do
  [ -f "$f" ] || continue
  n="$(LC_ALL=C awk '{n+=NF} END{print n+0}' "$f")"
  FOUND="${FOUND}${f#"${ROOT}/"}	${n}
"
done

if [ -z "$FOUND" ]; then
  err 'no files matched skills/*/SKILL.md or skills/*/references/*.md'
fi

while read -r limit path extra; do
  case "$limit" in '' | '#'*) continue ;; esac
  if [ -z "$path" ] || [ -n "$extra" ] || ! printf '%s\n' "$limit" | grep -Eq '^[1-9][0-9]*$'; then
    err "malformed line in tests/word-limits.txt: ${limit} ${path} ${extra}"
    continue
  fi
  if printf '%s' "$LISTED" | cut -f1 | grep -Fxq -- "$path"; then
    err "${path} is listed more than once in tests/word-limits.txt"
    continue
  fi
  LISTED="${LISTED}${path}	${limit}
"
done <"$LIST"

checked=0
while IFS="	" read -r path count; do
  [ -n "$path" ] || continue
  limit="$(printf '%s' "$LISTED" | awk -F'\t' -v p="$path" '$1 == p {print $2; exit}')"
  if [ -z "$limit" ]; then
    err "${path} is not listed in tests/word-limits.txt — add: ${count} ${path}"
  elif [ "$count" -gt "$limit" ]; then
    err "${path}: ${count} words, limit ${limit}"
  else
    checked=$((checked + 1))
  fi
done <<EOF2
${FOUND}
EOF2

while IFS="	" read -r path _; do
  [ -n "$path" ] || continue
  if ! printf '%s' "$FOUND" | cut -f1 | grep -Fxq -- "$path"; then
    err "${path} is listed but does not exist"
  fi
done <<EOF2
${LISTED}
EOF2

if [ "$errors" -ne 0 ]; then
  exit 1
fi
printf 'word-limits: %s files within their limits\n' "$checked"
