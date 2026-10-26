#!/usr/bin/env bash
# Check the judge handoff records for one implement-work completion-gate run:
# `judge-input-<round>.md` holds what the caller handed `judge-findings` and
# `judge-verdict-<round>.md` holds what it returned, per implement-work's
# references/measurement-record.md ("Judge input and verdict records"). A
# skipped judge step reads as a gap in these records: a missing verdict, a
# verdict-less fix, or a double record.
#
# Answers one line on stdout, exit 0, the first that applies:
#   MISSING <n>...    -- rounds 1..max with no input file
#   DOUBLE <n>...     -- a verdict naming another round's input, the same
#                        non-empty identity recorded as two rounds, or a verdict
#                        filed for an empty input
#   IDENTITY <n>...   -- Commit names no object, or Tree is not that commit's
#                        tree (a verdict authorising a fix on another tree)
#   GAP <n>...        -- an input item the verdict does not cover, an accept
#                        without its fix/value, or a rejected candidate dropped
#                        instead of re-offered
#   DIRTY             -- uncommitted changes; `git status --porcelain` on stderr
#   UNCOVERED <n>     -- the latest round's tree moved with no verdict, or with
#                        a verdict authorising no code change
#   OK                -- every record is present, whole, and covering
# Rounds are listed ascending, space-separated. A usage error prints
# `Usage: ...` on stderr, nothing on stdout, exit 2.
# Conventions: references/script-conventions.md.
#
# The record dir is this worktree's own git dir, never the common dir (the
# shared path rule of record-tree.sh / check-tree-records.sh): outside the
# tree, so neither check-clean.sh nor a commit sees it, and a sibling
# worktree's records never answer for this one.
#
# Round identity is the filename's number (`judge-input-<R>.md`), validated
# numeric and positive; anything else is not a round and is ignored. `max` is
# the highest round seen across input and verdict files, so a lone verdict for
# a round with no input still reports that round missing. Header matching is
# byte-exact after stripping trailing whitespace: a reworded header is a
# different header, which is exactly the silent `record`-to-fix failure the
# measurement record names.
# Usage: check-judge-records.sh
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: $0" >&2
  exit 2
fi

# shortcut: hunk-level attribution is not checked -- a fix commit touching
# files outside every accept still reads OK once any accept+apply exists;
# upgrade when a per-fix commit log exists.

RECORD_DIR="$(git rev-parse --absolute-git-dir)/dude-measurements/implement-work"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

INPUTS=""   # "round path" per line, rounds validated numeric and positive
VERDICTS="" # "round path" per line, same validation

if [ -d "$RECORD_DIR" ]; then
  f=""
  for f in "$RECORD_DIR"/judge-input-*.md "$RECORD_DIR"/judge-verdict-*.md; do
    [ -e "$f" ] || continue
    base="${f##*/}"
    case "$base" in
      judge-input-*.md)
        r="${base#judge-input-}"
        r="${r%.md}"
        is_input=1
        ;;
      judge-verdict-*.md)
        r="${base#judge-verdict-}"
        r="${r%.md}"
        is_input=0
        ;;
    esac
    case "$r" in
      '' | *[!0-9]*) continue ;;
    esac
    r="$((10#$r))"
    [ "$r" -le 0 ] && continue
    if [ "$is_input" -eq 1 ]; then
      INPUTS="${INPUTS}${r} ${f}
"
    else
      VERDICTS="${VERDICTS}${r} ${f}
"
    fi
  done
fi

# path_of <list> <round> -- the file recorded for that round, if any.
path_of() {
  local line
  line="$(printf '%s' "$1" | sed -n "s/^$2 //p" | sed -n '1p')"
  [ -n "$line" ] || return 1
  printf '%s' "$line"
}

# field <file> <key> -- the value of the first "Key: value" line, if any.
field() {
  sed -n "s/^$2: //p" "$1" 2>/dev/null | sed -n '1p'
}

# has_round <list> <round>
has_round() {
  path_of "$1" "$2" >/dev/null
}

# headers <file> -- the Finding:/Candidate: header lines, trailing whitespace
# stripped, so both sides compare the same bytes.
headers() {
  grep -h '^Finding: \|^Candidate: ' "$1" 2>/dev/null | sed 's/[[:space:]]*$//' || true
}

# max_round -- the highest round seen across both lists, 0 when neither holds
# any round.
max_round() {
  printf '%s%s' "$INPUTS" "$VERDICTS" | awk '$1>m{m=$1} END{print m+0}'
}

MAX="$(max_round)"

# ---- MISSING: rounds 1..max with no input file ---------------------------
MISSING=""
if [ "$MAX" -gt 0 ]; then
  r=1
  while [ "$r" -le "$MAX" ]; do
    if ! has_round "$INPUTS" "$r"; then
      MISSING="${MISSING} $r"
    fi
    r=$((r + 1))
  done
fi
if [ -n "$MISSING" ]; then
  echo "MISSING${MISSING}"
  exit 0
fi

# ---- DOUBLE ---------------------------------------------------------------
# A verdict naming another round's input file, the same non-empty identity
# recorded as two rounds (the Exit-batch double-run shape: the batch ran
# twice and recorded the same judgment as a new round), or a verdict filed
# for an empty input.
DOUBLE=""
if [ "$MAX" -gt 0 ]; then
  r=1
  while [ "$r" -le "$MAX" ]; do
    if has_round "$VERDICTS" "$r"; then
      vf="$(path_of "$VERDICTS" "$r")"
      if [ "$(field "$vf" 'Input')" != "judge-input-${r}.md" ]; then
        DOUBLE="${DOUBLE} $r"
      elif has_round "$INPUTS" "$r"; then
        inf="$(path_of "$INPUTS" "$r")"
        if [ -z "$(headers "$inf")" ]; then
          DOUBLE="${DOUBLE} $r"
        fi
      fi
    fi
    r=$((r + 1))
  done
  # Identical non-empty (Commit, Tree) in two input files. Empty-item rounds
  # are excluded: repeated clean polls legitimately re-record.
  r=1
  while [ "$r" -le "$MAX" ]; do
    if has_round "$INPUTS" "$r"; then
      inf="$(path_of "$INPUTS" "$r")"
      if [ -n "$(headers "$inf")" ]; then
        c_r="$(field "$inf" 'Commit')"
        t_r="$(field "$inf" 'Tree')"
        s=$((r + 1))
        while [ "$s" -le "$MAX" ]; do
          if has_round "$INPUTS" "$s"; then
            inf_s="$(path_of "$INPUTS" "$s")"
            if [ -n "$(headers "$inf_s")" ] &&
              [ "$(field "$inf_s" 'Commit')" = "$c_r" ] &&
              [ "$(field "$inf_s" 'Tree')" = "$t_r" ]; then
              case "$DOUBLE" in
                *" $r "*) ;;
                *) DOUBLE="${DOUBLE} $r" ;;
              esac
              case "$DOUBLE" in
                *" $s "*) ;;
                *) DOUBLE="${DOUBLE} $s" ;;
              esac
            fi
          fi
          s=$((s + 1))
        done
      fi
    fi
    r=$((r + 1))
  done
  if [ -n "$DOUBLE" ]; then
    # shellcheck disable=SC2086
    DOUBLE="$(printf '%s\n' $DOUBLE | sort -n | tr '\n' ' ')"
    DOUBLE=" ${DOUBLE% }"
    echo "DOUBLE${DOUBLE}"
    exit 0
  fi
fi

# ---- IDENTITY --------------------------------------------------------------
# Commit names no object, or Tree is not that commit's tree. The cat-file
# guard runs first and every rev-parse is failure-safe, so a bad commit
# answers IDENTITY instead of dying under `set -e`.
IDENTITY=""
if [ "$MAX" -gt 0 ]; then
  r=1
  while [ "$r" -le "$MAX" ]; do
    if has_round "$INPUTS" "$r"; then
      inf="$(path_of "$INPUTS" "$r")"
      c="$(field "$inf" 'Commit')"
      t="$(field "$inf" 'Tree')"
      if ! git cat-file -e "$c" 2>/dev/null; then
        IDENTITY="${IDENTITY} $r"
      else
        if ! wt="$(git rev-parse "${c}^{tree}" 2>/dev/null)"; then
          IDENTITY="${IDENTITY} $r"
        elif [ "$wt" != "$t" ]; then
          IDENTITY="${IDENTITY} $r"
        fi
      fi
    fi
    r=$((r + 1))
  done
fi
if [ -n "$IDENTITY" ]; then
  echo "IDENTITY${IDENTITY}"
  exit 0
fi

# ---- GAP --------------------------------------------------------------------
# An input item the verdict does not cover, an accept without its fix/value,
# or a rejected candidate dropped instead of re-offered in a later input. A
# declined candidate on the final round needs no re-offer. Closed/recorded
# ledger rows are never candidates and never appear in these files.
verdict_block() {
  # <stripped-verdict-file> <header>: the lines after that header up to the
  # next header or EOF.
  H="$2" awk '$0==ENVIRON["H"]{f=1;next} /^(Finding|Candidate): /{if(f)exit} f' "$1"
}

MAX_INPUT="$(printf '%s' "$INPUTS" | awk '$1>m{m=$1} END{print m+0}')"
GAP=""
if [ "$MAX_INPUT" -gt 0 ]; then
  r=1
  while [ "$r" -le "$MAX_INPUT" ]; do
    if has_round "$VERDICTS" "$r"; then
      inf="$(path_of "$INPUTS" "$r")"
      vf="$(path_of "$VERDICTS" "$r")"
      svf="${TMPD}/judge-verdict-${r}.stripped"
      sed 's/[[:space:]]*$//' "$vf" >"$svf"
      h=""
      while IFS= read -r h; do
        [ -n "$h" ] || continue
        block="$(verdict_block "$svf" "$h")"
        vline="$(printf '%s' "$block" | sed -n 's/^\(Verdict: .*\)/\1/p' | sed -n '1p')"
        case "$vline" in
          'Verdict: accept')
            if ! printf '%s' "$block" | grep -qE '^Value: (apply|record)$'; then
              case "$GAP" in
                *" $r "*) ;;
                *) GAP="${GAP} $r" ;;
              esac
            fi
            ;;
          'Verdict: reject' | 'Verdict: needs-user')
            ;;
          *)
            case "$GAP" in
              *" $r "*) ;;
              *) GAP="${GAP} $r" ;;
            esac
            ;;
        esac
        case "$h" in
          'Candidate: '*)
            if [ "$vline" = 'Verdict: reject' ] && [ "$r" -lt "$MAX_INPUT" ]; then
              s=$((r + 1))
              found=0
              while [ "$s" -le "$MAX_INPUT" ]; do
                if has_round "$INPUTS" "$s"; then
                  if printf '%s\n' "$(headers "$(path_of "$INPUTS" "$s")")" | grep -qFx -- "$h"; then
                    found=1
                    break
                  fi
                fi
                s=$((s + 1))
              done
              if [ "$found" -eq 0 ]; then
                case "$GAP" in
                  *" $r "*) ;;
                  *) GAP="${GAP} $r" ;;
                esac
              fi
            fi
            ;;
        esac
      done <<HEADERS_EOF
$(headers "$inf")
HEADERS_EOF
      # An input header with no same line in the verdict never reached the
      # judge.
      if grep -qFxvf "$svf" <<HEADERS_EOF2; then
$(headers "$inf")
HEADERS_EOF2
        case "$GAP" in
          *" $r "*) ;;
          *) GAP="${GAP} $r" ;;
        esac
      fi
    fi
    r=$((r + 1))
  done
fi
if [ -n "$GAP" ]; then
  # shellcheck disable=SC2086
  GAP="$(printf '%s\n' $GAP | sort -n | tr '\n' ' ')"
  GAP=" ${GAP% }"
  echo "GAP${GAP}"
  exit 0
fi

# ---- DIRTY -------------------------------------------------------------------
# What is pushed is commits only, so an edit still in the tree is not
# delivered even when every record matches. The flag overrides
# status.showUntrackedFiles=no, under which an untracked file created after
# the records is invisible here: DIRTY.
PENDING="$(git status --porcelain --untracked-files=normal)"
if [ -n "$PENDING" ]; then
  echo "DIRTY"
  printf '%s\n' "$PENDING" >&2
  exit 0
fi

# ---- UNCOVERED ------------------------------------------------------------------
# The latest round's tree moved with no verdict (the judge bypassed), or with
# a verdict authorising no code change (`reject`, `needs-user`, and
# `record`-only all authorise none). First-parent only: a base absorb merged
# in after judging advances the second-parent side, so it stays OK. An empty
# latest input is nothing to cover.
if [ "$MAX_INPUT" -gt 0 ]; then
  inf="$(path_of "$INPUTS" "$MAX_INPUT")"
  if [ -n "$(headers "$inf")" ]; then
    c="$(field "$inf" 'Commit')"
    moved=""
    if [ -n "$(git rev-list --first-parent --no-merges "${c}..HEAD" 2>/dev/null || true)" ]; then
      moved=1
    fi
    if [ -n "$moved" ]; then
      if ! has_round "$VERDICTS" "$MAX_INPUT"; then
        echo "UNCOVERED ${MAX_INPUT}"
        exit 0
      fi
      vf="$(path_of "$VERDICTS" "$MAX_INPUT")"
      svf="${TMPD}/judge-verdict-${MAX_INPUT}.stripped"
      sed 's/[[:space:]]*$//' "$vf" >"$svf"
      authorised=0
      h=""
      while IFS= read -r h; do
        [ -n "$h" ] || continue
        block="$(verdict_block "$svf" "$h")"
        if printf '%s' "$block" | grep -q '^Verdict: accept$' &&
          printf '%s' "$block" | grep -q '^Value: apply$'; then
          authorised=1
          break
        fi
      done <<HEADERS_EOF
$(headers "$inf")
HEADERS_EOF
      if [ "$authorised" -eq 0 ]; then
        echo "UNCOVERED ${MAX_INPUT}"
        exit 0
      fi
    fi
  fi
fi

echo "OK"
