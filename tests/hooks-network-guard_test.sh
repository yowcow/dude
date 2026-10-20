#!/usr/bin/env bash
# Canonical non-gh network guard for hooks/: sample denylist (curl/wget-class,
# not exhaustive — sweep excluded per #446). `gh` itself stays covered by
# session-start_test.sh's zero-gh rows (gh calls == 0), so the two failure
# shapes are separable: a `gh` addition fails there, a curl/wget addition
# fails here.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

failed=0
total=0

# `gh` is deliberately absent from this list: it is the kept zero-gh guard's
# domain. `hooks.json` is exempt (JSON manifest, covered by make manifest).
# network_hits <dir> -- the denylist hits under <dir> on stdout; 0 on a read
# (with or without hits), and grep's own status otherwise, so the caller can
# tell "no hits" from "never read" and name the reason.
# shellcheck disable=SC2317 # reached only from the checks `tally` invokes
network_hits() {
  local out status=0
  out="$(grep -R -E -n --exclude=hooks.json \
    -e '(^|[^a-zA-Z0-9_-])(curl|wget)([^a-zA-Z0-9_-]|$)' \
    -e '(^|[^a-zA-Z0-9_-])(ssh|nc|socat)([^a-zA-Z0-9_-]|$)' \
    -e 'urllib|HttpClient|socket\.|fetch[[:space:]]*\(|XMLHttpRequest' \
    -e 'git[[:space:]]+(ls-remote|clone|fetch|pull|push)[[:space:]]+[^.]*(https?://|ssh://|git@)' \
    -e '(^|[^a-zA-Z0-9_-])(npm|pip)[[:space:]]+install' \
    "$1" 2>/dev/null)" || status=$?
  # 1 is "read, no match". Anything else — 2 on a bad pattern or a tree grep
  # could not read — means the scan never happened, and answering that with "no
  # hits" is a green gate over an unread tree.
  case "$status" in
    0) printf '%s' "$out" ;;
    1) ;;
    *) return "$status" ;;
  esac
}

# The three verdicts the scan can reach, one check each.
# shellcheck disable=SC2317 # reached as a command name by tally
check_clean() {
  local label="$1" dir="$2" hits status=0
  hits="$(network_hits "$dir")" || status=$?
  if [ "$status" -ne 0 ]; then
    printf 'FAIL %s: the scan could not complete for %s (grep exit %s)\n' \
      "$label" "$dir" "$status" >&2
    return 1
  fi
  if [ -n "$hits" ]; then
    printf 'FAIL %s: non-gh network primitive found:\n%s\n' "$label" "$hits" >&2
    return 1
  fi
}
# shellcheck disable=SC2317
check_hits() {
  local label="$1" dir="$2" hits status=0
  hits="$(network_hits "$dir")" || status=$?
  if [ "$status" -ne 0 ]; then
    printf 'FAIL %s: the scan could not complete for %s (grep exit %s)\n' \
      "$label" "$dir" "$status" >&2
    return 1
  fi
  if [ -z "$hits" ]; then
    printf 'FAIL %s: a curl line was not reported\n' "$label" >&2
    return 1
  fi
}
# shellcheck disable=SC2317
check_unreadable() {
  local label="$1" dir="$2"
  if network_hits "$dir" >/dev/null; then
    printf 'FAIL %s: an unreadable tree was reported as no hits\n' "$label" >&2
    return 1
  fi
}

# The gate: the real hooks/ must be clean.
tally check_clean 'real hooks/' "$REPO_ROOT/hooks"

# The scan still finds a primitive when there is one, so the rows below cannot
# pass by the matcher being broken.
HIT_DIR="$(mktemp -d "${HARNESS_TMP}/hit.XXXXXX")"
printf 'curl -sS https://example.com\n' >"$HIT_DIR/fetch"
tally check_hits 'a planted curl' "$HIT_DIR"

CLEAN_DIR="$(mktemp -d "${HARNESS_TMP}/clean.XXXXXX")"
printf 'echo hi\n' >"$CLEAN_DIR/ok"
tally check_clean 'a clean tree' "$CLEAN_DIR"

# grep exits 2 on a directory that is not there — root-proof, unlike chmod 000,
# which uid 0 reads anyway. The old `|| true` answered this with "no hits".
tally check_unreadable 'a missing tree' "${HARNESS_TMP}/no-such-hooks"

harness_exit "$failed" "$total"
