#!/usr/bin/env bash
# The shared half of the facts contract: the self-check a script runs before
# it uses a GitHub fact, the read that follows it, and the WAIT round counter.
#
# A facts file holds one `name=value` per line; a list repeats its name once
# per element and carries `<name>.total`, the count its source reported.
# Format and catalogue: skills/implement-work/references/facts.md.
#
# `check` prints one line its caller relays verbatim. Each self-check stops a
# wrong record from reaching the caller's decision:
#   identifier (`name=value`) — another record than the one asked for was
#     read; measured over MCP, a head filter without its owner is ignored and
#     unrelated PRs come back.
#   count (`name[]`, or a scalar given twice) — a list shorter than its total
#     is a truncated page, read as the whole list.
#   enum (`name:A,B`) — a value outside the set the caller branches on.
#   unfilled — an empty value or `null`, which is what an unreadable field
#     becomes when it is written anyway; a fact is never guessed.
#
# `wait` counts the rounds of a WAIT. The state lives in a file this script
# writes and the agent hands back unchanged, so a missing or unrecognised
# state file is a STOP rather than a count restarted from zero: a restart waits past the
# limit the porting script inherited.
# Only a file carrying the `dude-wait` mark is one this script wrote: a caller's
# file that merely spells `round=N` would otherwise be rewritten and removed.
#
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: facts.sh check <facts-file|''> <spec>...
#        facts.sh get <facts-file> <name>
#        facts.sh wait <state-file|''> <limit> <seconds> <final-word>
# Output (check): OK | NEED <token>... | STOP <slug>
# Output (get): the values recorded under <name>, one per line
# Output (wait): WAIT <seconds> <state-file> | <final-word> | STOP wait-state-invalid
set -euo pipefail

usage() {
  echo "Usage: $0 check <facts-file|''> <spec>... | get <facts-file> <name> | wait <state-file|''> <limit> <seconds> <final-word>" >&2
  exit 2
}

NAME_RE='^[a-z0-9._-]+$'
PAD_RE='^[[:space:]]|[[:space:]]$'
STATE_RE='^dude-wait round=([1-9][0-9]*)$'

STATE_OWNED=''

# The state file this script created, removed on every exit that does not hand
# it back: the caller learns the path only from the WAIT line, so a run that
# fails before printing it leaves a file nothing will ever name.
cleanup() {
  if [ -n "$STATE_OWNED" ]; then
    rm -f -- "$STATE_OWNED" || true
  fi
}
trap cleanup EXIT

# spec_name <spec>: the fact name inside `name`, `name=v`, `name:A,B`, `name[]`.
spec_name() {
  local n="${1%%=*}"
  n="${n%%:*}"
  printf '%s\n' "${n%\[\]}"
}

# values <file> <name>: every value recorded under <name>, one per line.
values() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$2="*) printf '%s\n' "${line#*=}" ;;
    esac
  done <"$1"
}

# count <file> <name>: how many lines record <name>.
count() {
  values "$1" "$2" | wc -l | tr -d ' '
}

unfilled() {
  [ -z "$1" ] || [ "$1" = null ]
}

# verify <file> <spec>: prints the slug of the first failed self-check, or
# nothing.
verify() {
  local file="$1" spec="$2" name total v
  name="$(spec_name "$spec")"
  case "$spec" in
    *'[]')
      total="$(values "$file" "${name}.total")"
      if [ "$(count "$file" "${name}.total")" -ne 1 ]; then echo fact-count; return; fi
      if unfilled "$total"; then echo fact-missing; return; fi
      if ! [[ "$total" =~ ^[0-9]+$ ]] || ! [ "$(count "$file" "$name")" -eq "$total" ]; then
        echo fact-count
        return
      fi
      while IFS= read -r v; do
        if unfilled "$v"; then echo fact-missing; return; fi
      done < <(values "$file" "$name")
      return
      ;;
  esac
  if [ "$(count "$file" "$name")" -ne 1 ]; then echo fact-count; return; fi
  v="$(values "$file" "$name")"
  if unfilled "$v"; then echo fact-missing; return; fi
  case "$spec" in
    *=*) if [ "$v" != "${spec#*=}" ]; then echo fact-mismatch; fi ;;
    *:*)
      case "$v" in *,*) echo fact-enum; return ;; esac
      case ",${spec#*:}," in
        *",${v},"*) ;;
        *) echo fact-enum ;;
      esac
      ;;
  esac
}

check() {
  local file="$1" spec name key line need='' slug
  shift
  for spec in "$@"; do
    if ! [[ "$(spec_name "$spec")" =~ $NAME_RE ]]; then usage; fi
  done
  if [ -n "$file" ]; then
    if [ ! -r "$file" ]; then echo "STOP fact-malformed"; return; fi
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      if [ "$line" = "${line%%=*}" ] || ! [[ "${line%%=*}" =~ $NAME_RE ]] ||
        [[ "${line#*=}" =~ $PAD_RE ]]; then
        echo "STOP fact-malformed"
        return
      fi
    done <"$file"
  fi
  for spec in "$@"; do
    name="$(spec_name "$spec")"
    key="$name"
    case "$spec" in *'[]') key="${name}.total" ;; esac
    if [ -z "$file" ] || [ "$(count "$file" "$key")" -eq 0 ]; then
      case "$spec" in
        *=*) need="${need} ${spec}" ;;
        *) need="${need} ${name}" ;;
      esac
    fi
  done
  if [ -n "$need" ]; then
    echo "NEED${need}"
    return
  fi
  for spec in "$@"; do
    slug="$(verify "$file" "$spec")"
    if [ -n "$slug" ]; then
      echo "STOP ${slug}"
      return
    fi
  done
  echo OK
}

wait_round() {
  local state="$1" limit="$2" seconds="$3" final="$4" round=0 line
  if ! [[ "$limit" =~ ^[1-9][0-9]*$ ]] || ! [[ "$seconds" =~ ^[0-9]+$ ]] ||
    ! [[ "$final" =~ ^[A-Z][A-Z-]*$ ]]; then
    usage
  fi
  if [ -z "$state" ]; then
    state="$(mktemp "${TMPDIR:-/tmp}/dude-wait.XXXXXX")"
    STATE_OWNED="$state"
  else
    if [ ! -f "$state" ] || ! line="$(cat -- "$state")" ||
      ! [[ "$line" =~ $STATE_RE ]]; then
      echo "STOP wait-state-invalid"
      return
    fi
    round="${BASH_REMATCH[1]}"
  fi
  round=$((round + 1))
  if [ "$round" -ge "$limit" ]; then
    rm -f -- "$state"
    STATE_OWNED=''
    echo "$final"
    return
  fi
  printf 'dude-wait round=%s\n' "$round" >"$state"
  echo "WAIT ${seconds} ${state}"
  STATE_OWNED=''
}

[ "$#" -ge 1 ] || usage
cmd="$1"
shift
case "$cmd" in
  check)
    [ "$#" -ge 2 ] || usage
    check "$@"
    ;;
  get)
    [ "$#" -eq 2 ] || usage
    [[ "$2" =~ $NAME_RE ]] || usage
    values "$1" "$2"
    ;;
  wait)
    [ "$#" -eq 4 ] || usage
    wait_round "$@"
    ;;
  *) usage ;;
esac
