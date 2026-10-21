#!/usr/bin/env bash
# Build a PR review payload -- {body, comments} -- from a summary and the
# accepted findings, putting each finding where GitHub will take it.
#
# A finding goes inline only on a line the reviewed diff adds: GitHub refuses
# a review comment on a line outside the diff, and one refused comment fails
# the whole review. Everything else -- a finding on an unchanged line, on a
# file the PR did not touch, or with no line at all -- goes into the body under
# its path and line. "Adds" is measured with --unified=0 on a rename-aware diff
# of the whole range (see ADDED), changed lines only:
# GitHub also accepts the context lines around a hunk, but its diff and this
# one need not cut hunks alike, and a finding moved to the body is still
# posted where a refused one takes the review down with it.
#
# <findings-file> is a JSON array of {path, line, body}; path and line may be
# null, and line is a head-side line number. Severity and the proposed fix are
# part of each body; this script does not read them.
#
# Conventions: ../../implement-work/references/script-conventions.md.
#
# Usage: build-review-payload.sh <base-sha> <head-sha> <summary-file> <findings-file>
# Output: one line of JSON, {"body":...,"comments":[{"path","line","side","body"}]}
set -euo pipefail

# Checked before any argument: without jq the guard below answers usage, and the
# caller edits its argv instead of the missing dependency.
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but was not found on PATH" >&2
  exit 1
fi

if [ "$#" -ne 4 ] || [ ! -r "$3" ] || [ ! -r "$4" ] ||
  ! jq -e 'type == "array"' "$4" >/dev/null 2>&1; then
  echo "Usage: $0 <base-sha> <head-sha> <summary-file> <findings-file>" >&2
  exit 2
fi

BASE="$1"
HEAD="$2"
SUMMARY="$3"
FINDINGS="$4"

# ADDED: one "<path>\t<start>\t<count>" per hunk, head side, from ONE
# rename-aware diff of the whole range. A pathspec naming only the new path
# hides the rename and makes every line of a renamed file look added; -M is
# explicit because diff.renames may be off, and the prefixes and quotePath are
# pinned because the header parse below depends on them. A `+++` line is a
# header only between a `diff --git` line and its first `@@`, so an added line
# whose text starts with `++ b/` is never read as one. A deleted file
# (`+++ /dev/null`) and a 100% rename (no `+++`, no hunk) yield no rows, so
# findings on them go to the body.
ADDED="$(git -c core.quotePath=false diff -M --no-color --no-ext-diff \
  --src-prefix=a/ --dst-prefix=b/ --unified=0 "$BASE" "$HEAD" | awk '
  /^diff --git / { hdr = 1; path = ""; next }
  hdr && /^\+\+\+ / { p = substr($0, 5); sub(/\t$/, "", p)
                      path = (p ~ /^b\//) ? substr(p, 3) : ""; next }
  /^@@ / { hdr = 0; if (path == "") next
           r = $3; sub(/^\+/, "", r); n = split(r, a, ",")
           print path "\t" a[1] "\t" (n > 1 ? a[2] : 1) }')"

# in_diff <path> <line>: succeeds when <line> is a line BASE..HEAD adds to
# <path>, per ADDED. A hunk header reads `@@ -a[,b] +c[,d] @@`; the added lines
# are c .. c+d-1, with d defaulting to 1 and d=0 adding none.
in_diff() {
  local path="$1" line="$2" p start count
  [[ "$line" =~ ^[0-9]+$ ]] || return 1
  while IFS=$'\t' read -r p start count; do
    [ "$p" = "$path" ] || continue
    if [ "$line" -ge "$start" ] && [ "$line" -lt $((start + count)) ]; then
      return 0
    fi
  done <<<"$ADDED"
  return 1
}

INLINE=''
i=0
while IFS=$'\t' read -r path line; do
  if [ -n "$path" ] && in_diff "$path" "$line"; then
    INLINE="${INLINE:+${INLINE},}${i}"
  fi
  i=$((i + 1))
done < <(jq -r '.[] | [(.path // ""), (.line // "" | tostring)] | @tsv' "$FINDINGS")

jq -c --rawfile summary "$SUMMARY" --argjson inline "[${INLINE}]" '
  . as $f
  | [range(0; length) | select(. as $i | $inline | any(.[]; . == $i) | not) | $f[.]
     | "- " + (if .path then "`" + .path + (if .line then ":" + (.line | tostring) else "" end) + "`: " else "" end) + (.body | gsub("\n"; "\n  "))]
    as $out
  | {body: (($summary | rtrimstr("\n")) + (if ($out | length) > 0 then "\n\n" + ($out | join("\n")) else "" end)),
     comments: [$inline[] | $f[.] | {path, line, side: "RIGHT", body}]}' "$FINDINGS"
