#!/usr/bin/env bash
# Make a sub-issue's native "blocked by" set exactly the prerequisites given, and
# print what it ended up as. Declarative on purpose: pass the prerequisites the
# item has now, and this adds what is missing and removes what is no longer
# required. Pass none at all for an item that is independent.
#
# Why the relation is set at all, and why it is read back: `implement-work`
# branches on blockedBy.totalCount to pick a base branch. A relation that failed
# to stick leaves the count at 0, so a stacked item silently branches off the
# default branch instead of its prerequisite's PR — and a stale relation left
# behind on an item that has become independent stops it just as silently. Neither
# shows up as an error, so the resulting set is compared against the intended one
# here and a mismatch exits non-zero.
#
# The body's prerequisite line is a separate record, for the human, and carries
# the reason. Neither replaces the other.
#
# Usage: set-prerequisites.sh <owner> <repo> <child-number> [<prereq-number>...]
# Output: the resulting blocked-by count and numbers
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <owner> <repo> <child-number> [<prereq-number>...]" >&2
  echo "       pass no prerequisite numbers to make the item independent" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
CHILD="$3"
shift 3

for n in "$CHILD" "$@"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "error: invalid issue number '$n' (must be an integer)" >&2
    exit 1
  fi
done

for n in "$@"; do
  if [ "$n" = "$CHILD" ]; then
    echo "error: #$CHILD cannot be blocked by itself" >&2
    exit 1
  fi
done

# printf with no arguments would emit one empty line, which comm would then treat
# as a member of the set — so emit nothing for an empty set.
emit() {
  if [ -n "$1" ]; then printf '%s\n' "$1"; fi
}

# The same set, on one line, for the messages below.
oneline() {
  emit "$1" | tr '\n' ' '
}

# Sorted lexically, not numerically: comm below compares its inputs lexically and
# silently produces the wrong difference when handed numerically-sorted lines
# (`9` before `12`). Both sides use the same order so the sets and the final
# equality check all agree.
read_blocked_by() {
  gh issue view "$CHILD" --repo "$OWNER/$REPO" --json blockedBy \
    --jq '.blockedBy.nodes[].number' | sort -u
}

CURRENT=$(read_blocked_by)
DESIRED=""
if [ "$#" -gt 0 ]; then
  DESIRED=$(printf '%s\n' "$@" | sort -u)
fi

TO_ADD=$(comm -13 <(emit "$CURRENT") <(emit "$DESIRED"))
TO_REMOVE=$(comm -23 <(emit "$CURRENT") <(emit "$DESIRED"))

EDIT_ARGS=()
while read -r n; do
  if [ -n "$n" ]; then EDIT_ARGS+=(--add-blocked-by "$n"); fi
done <<<"$TO_ADD"
while read -r n; do
  if [ -n "$n" ]; then EDIT_ARGS+=(--remove-blocked-by "$n"); fi
done <<<"$TO_REMOVE"

if [ "${#EDIT_ARGS[@]}" -gt 0 ]; then
  gh issue edit "$CHILD" --repo "$OWNER/$REPO" "${EDIT_ARGS[@]}" >/dev/null
fi

FINAL=$(read_blocked_by)
if [ "$FINAL" != "$DESIRED" ]; then
  echo "error: #$CHILD is blocked by [$(oneline "$FINAL")]," >&2
  echo "       intended [$(oneline "$DESIRED")]" >&2
  exit 1
fi

COUNT=$(emit "$FINAL" | wc -l | tr -d ' ')
echo "#$CHILD blocked-by count: $COUNT [$(oneline "$FINAL")]"
