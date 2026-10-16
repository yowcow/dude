#!/usr/bin/env bash
# The dependency gate for skills/: the layer map, the upward and lateral edges
# kept on purpose with their reasons, and the checks. AUTHORING.md's
# "Dependencies point down" points here.
#
# An edge is owner -> target: a file under skills/<owner>/ names <target> by
# name, or by a glob such as `investigate-*`, which counts as an edge to every
# skill the prefix matches. using-dude is neither owner nor target: every skill
# may name it. Only an edge's presence is checked, never how many mentions it
# has, so editing a flow's prose does not move this file.
#
# Usage: tests/skill-deps_test.sh [<root>]   — <root> defaults to this repository.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

ROOT="${1:-$REPO_ROOT}"

# <skill or glob> <layer>. Layers, top down: flow, part, component, primitive.
LAYERS='plan-work flow
implement-work flow
pr-to-ready flow
review-code part
review-plan part
simplify-code part
review-pr part
audit-code part
investigate-* part
settle-question part
vet-code component
review-findings component
judge-findings primitive'

# <owner> <target> <reason>. Every upward or lateral edge must have a row, and
# every row must still have a mention.
EDGES='plan-work implement-work hand-off: the published TODO list is shaped for implement-work to pick up one item.
implement-work plan-work hand-back: work larger than one PR and an invalidated design go back to plan-work, whose **Entry** says what it does with them.
implement-work pr-to-ready hand-off, plus contracts: **Hand off** continues into pr-to-ready, and references/ holds the STOP registry and Base-Branch contract that pr-to-ready'"'"'s scripts implement.
pr-to-ready implement-work hand-off: its input is the draft PR implement-work left, title and body follow implement-work'"'"'s **Hand off**, and a drifted base is sent back there.
pr-to-ready plan-work hand-back: Escalation hands plan-work'"'"'s entry the finding, the branch, and its state.
review-code implement-work contract (PR #549 R6): cites the Base-Branch trailer contract in implement-work/references/base-branch.md, its single source.
review-pr implement-work contract: script headers cite implement-work/references/script-conventions.md and stop-registry.md, the shared conventions.
audit-code plan-work contract (#559 hand-off): cites plan-work'"'"'s question-shaped **Entry**, the shape its report is written to; using-dude names no destination for audit-code.'

failed=0
total=0

# rank_of <skill> — 1 flow, 2 part, 3 component, 4 primitive; prints nothing when unmapped.
rank_of() {
  local pat layer
  while read -r pat layer; do
    # shellcheck disable=SC2254  # $pat is a glob on purpose: investigate-*
    case "$1" in
      $pat)
        case "$layer" in
          flow) echo 1 ;;
          part) echo 2 ;;
          component) echo 3 ;;
          primitive) echo 4 ;;
        esac
        return 0
        ;;
    esac
  done <<<"$LAYERS"
}

in_table() {
  printf '%s\n' "$EDGES" | grep -qE "^$1 $2 "
}

# --- enumeration -------------------------------------------------------------
# Into files through a plain pipeline, so a find that dies partway fails the run
# instead of leaving a green over what it managed to read.
dirs="${HARNESS_TMP}/dirs"
files="${HARNESS_TMP}/files"
if ! find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -print | sort >"$dirs" ||
  ! find "$ROOT/skills" -path "$ROOT/skills/using-dude" -prune -o \( -type f -o -type l \) -print | sort >"$files"; then
  echo "skill-deps: listing $ROOT/skills failed — the tree was not fully read" >&2
  exit 1
fi

skills=()
while IFS= read -r d; do
  [ "${d##*/}" = using-dude ] || skills+=("${d##*/}")
done <"$dirs"

# A broken enumerator and a clean tree are otherwise the same green.
broken() {
  printf 'skill-deps: %s skill(s), %s file(s), %s mention(s) under %s — the enumeration is broken\n' \
    "${#skills[@]}" "${nfiles:-0}" "${nmentions:-0}" "$ROOT/skills" >&2
  exit 1
}
# Checked before any loop over skills: "${skills[@]}" on an empty array is an
# unbound-variable error under set -u before bash 4.4.
if [ "${#skills[@]}" -eq 0 ]; then
  broken
fi

# mentions: "<owner> <target> <file>:<line>", one per mention.
mentions="${HARNESS_TMP}/mentions"
: >"$mentions"
nfiles=0
while IFS= read -r f; do
  nfiles=$((nfiles + 1))
  rel="${f#"$ROOT"/}"
  owner="${rel#skills/}"
  owner="${owner%%/*}"
  for t in "${skills[@]}"; do
    [ "$t" != "$owner" ] || continue
    grep -nE "(^|[^a-z0-9-])${t}([^a-z0-9-]|$)" "$f" | cut -d: -f1 |
      sed "s|^|${owner} ${t} ${rel}:|" >>"$mentions" || true
  done
  grep -noE '(^|[^a-z0-9-])[a-z0-9]+(-[a-z0-9]+)*-\*' "$f" |
    sed -E 's/^([0-9]+):[^a-z0-9-]?([a-z0-9-]+)-\*$/\1 \2/' |
    while read -r line prefix; do
      for t in "${skills[@]}"; do
        [ "$t" != "$owner" ] || continue
        case "$t" in "$prefix"-*) echo "${owner} ${t} ${rel}:${line}" ;; esac
      done
    done >>"$mentions" || true
done <"$files"

nmentions="$(wc -l <"$mentions" | tr -d ' ')"
if [ "$nfiles" -eq 0 ] || [ "$nmentions" -eq 0 ]; then
  broken
fi

# --- every skill is on the map -----------------------------------------------
total=$((total + 1))
bad=0
for s in "${skills[@]}"; do
  if [ -z "$(rank_of "$s")" ]; then
    printf 'FAIL skill-deps: %s is not in the layer map\n' "$s"
    bad=1
  fi
done
failed=$((failed + bad))

# --- every upward or lateral edge has a row ----------------------------------
total=$((total + 1))
bad=0
while read -r owner target where; do
  ro="$(rank_of "$owner")"
  rt="$(rank_of "$target")"
  # An unmapped skill is already reported above.
  if [ -z "$ro" ] || [ -z "$rt" ] || [ "$rt" -gt "$ro" ]; then continue; fi
  if ! in_table "$owner" "$target"; then
    printf 'FAIL skill-deps: %s -> %s points up or sideways and has no row in EDGES (first at %s)\n' \
      "$owner" "$target" "$where"
    bad=1
  fi
done < <(awk '!seen[$1" "$2]++' "$mentions")
failed=$((failed + bad))

# --- every row still has a mention -------------------------------------------
total=$((total + 1))
bad=0
while read -r owner target _; do
  if ! grep -qE "^${owner} ${target} " "$mentions"; then
    printf 'FAIL skill-deps: EDGES row %s -> %s is stale: no mention is left\n' "$owner" "$target"
    bad=1
  fi
done <<<"$EDGES"
failed=$((failed + bad))

# --- no skill borrows another skill's Orchestration model --------------------
# Allow-listed phrasings are stripped first, so any "orchestration" left over is
# a borrowing however it is worded; a possessive of another skill followed by
# orchestration, dispatch, or worker is the paraphrase that avoids the word.
total=$((total + 1))
bad=0
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  owner="${rel#skills/}"
  owner="${owner%%/*}"
  while IFS= read -r hit; do
    n="${hit%%:*}"
    text="${hit#*:}"
    if [ "$text" = '## Orchestration model' ] && [ "${f##*/}" = SKILL.md ]; then continue; fi
    rest="$(printf '%s\n' "$text" |
      sed -E -e "s/[Tt]his skill's (\*\*)?Orchestration model(\*\*)?//g" \
        -e 's#\.\./SKILL\.md, "Orchestration##g' | tr '[:upper:]' '[:lower:]')"
    case "$rest" in
      *orchestration*)
        printf 'FAIL skill-deps: %s:%s borrows an Orchestration model: %s\n' "$rel" "$n" "$text"
        bad=1
        ;;
    esac
  done < <(grep -niE 'orchestration' "$f" || true)
  for t in "${skills[@]}"; do
    [ "$t" != "$owner" ] || continue
    while IFS= read -r hit; do
      printf 'FAIL skill-deps: %s:%s borrows %s'"'"'s orchestration: %s\n' "$rel" "${hit%%:*}" "$t" "${hit#*:}"
      bad=1
    done < <(grep -nE "(^|[^a-z0-9-])${t}\`?'s? (\*\*)?[A-Za-z ]{0,20}([Oo]rchestrat|[Dd]ispatch|[Ww]orker)" "$f" || true)
  done
done <"$files"
failed=$((failed + bad))

# --- no path into another skill's scripts/ -----------------------------------
total=$((total + 1))
bad=0
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  owner="${rel#skills/}"
  owner="${owner%%/*}"
  while IFS= read -r d; do
    t="${d##*/}"
    [ "$t" != "$owner" ] || continue
    while IFS= read -r hit; do
      printf 'FAIL skill-deps: %s:%s names a path into %s/scripts/: %s\n' "$rel" "${hit%%:*}" "$t" "${hit#*:}"
      bad=1
    done < <(grep -nE "(^|[^a-z0-9-])${t}/scripts([^a-z0-9-]|$)" "$f" || true)
  done <"$dirs"
done <"$files"
failed=$((failed + bad))

printf 'skill-deps: %s skill(s), %s file(s), %s mention(s)\n' "${#skills[@]}" "$nfiles" "$nmentions"
harness_exit "$failed" "$total"
