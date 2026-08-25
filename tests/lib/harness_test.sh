#!/usr/bin/env bash
# Self-test of the harness mechanism. The properties tested here are the ones
# the suite's trustworthiness rests on: an argv nobody stubbed must fail the
# case instead of reaching the real `gh` (and the network), the stub must count
# calls so a poll loop's second iteration can differ from its first, stdout must
# be compared byte-for-byte — a defect whose whole signature is one stray
# newline is invisible to a line-count comparison — an argv the manifest cannot
# disambiguate from another must be refused when stubbed rather than never
# matching, and the call index must count invocations rather than lines of argv.
# An argv spanning lines must be stubbable and must match only itself. `--jq`
# must be applied to a successful body and never to a failing one. One
# `--paginate` invocation must serve a page sequence, truncating at a failing
# page. And a stubbed body that `--jq` cannot filter is a broken fixture or a
# broken filter, not a modelled `gh` failure, so it must be reported loudly
# rather than degrading into an ordinary exit 1 — a quiet failure there would
# recreate, inside the stub itself, the very absent-versus-could-not-ask
# confusion this suite exists to catch. And an expectation the harness cannot
# read must be named as such, rather than compared against as far as it got and
# charged to the script under test. And the payload of an `--input -` call must
# be recorded, with its absence its own failure distinct from a byte mismatch —
# without it, the three `plan-work` posting scripts' stdin-piped body is
# unobservable, since it never reaches the argv the stub matches on.
#
# The eleven numbered blocks below run in that order, matching the numbered list
# in tests/README.md. The blocks after them cover the other two pieces of
# machinery the suite rests on: the disposable git repository helper and the
# `sleep` stub.
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean — verified clean under
# `shellcheck -x` too, so item 2's CI is free to invoke it either way.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/gitrepo.sh"

failed=0
total=0

# --- property 1: an argv with no manifest entry fails the case -----------------
total=$((total + 1))
stub_dir_new
gh_stub_response '*' 0 api "repos/acme/widgets/commits/deadbeef/check-runs" </dev/null
status=0
gh api "repos/acme/widgets/pulls/1" >/dev/null 2>&1 || status=$?
fails_here=0
if ! check_eq "unexpected argv: gh exit status" 99 "$status"; then fails_here=1; fi
if check_no_violations "unexpected argv: probe" >/dev/null 2>&1; then
  echo "FAIL unexpected argv: no violation was recorded"
  fails_here=1
fi
if ! check_eq "unexpected argv: call is still counted" 1 "$(gh_call_count)"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 2: the call counter selects per-call responses -------------------
total=$((total + 1))
stub_dir_new
gh_stub_response 1 0 api one <<<'first'
gh_stub_response 2 0 api one <<<'second'
gh_stub_response '*' 0 api one <<<'later'
fails_here=0
if ! check_eq "counter: call 1" 'first' "$(gh api one)"; then fails_here=1; fi
if ! check_eq "counter: call 2" 'second' "$(gh api one)"; then fails_here=1; fi
if ! check_eq "counter: call 3 falls back to *" 'later' "$(gh api one)"; then fails_here=1; fi
if ! check_eq "counter: total" 3 "$(gh_call_count)"; then fails_here=1; fi
if ! check_no_violations "counter: no violations"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 3: stdout is compared byte-for-byte -----------------------------
# A bare newline and no output are the same number of lines and different bytes.
total=$((total + 1))
stub_dir_new
fails_here=0
run_sut printf '\n'
if check_bytes "bytes: probe expects a mismatch" '' >/dev/null 2>&1; then
  echo "FAIL bytes: one stray newline compared equal to no output"
  fails_here=1
fi
if ! check_bytes "bytes: newline matches newline" '\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 4: only an argv the manifest cannot disambiguate is rejected ----
# The joined argv lives in its own file, so a tab or a newline inside an element
# is representable and must match. \x1f is different in kind: it is the element
# separator, so ["a\x1fb"] and ["a","b"] join to the same bytes and one case's
# body would be served to the other. That one stays refused.
total=$((total + 1))
stub_dir_new
fails_here=0
status=0
gh_stub_response 1 0 api "$(printf 'a\x1fb')" </dev/null 2>/dev/null || status=$?
if ! check_eq "helper rejects \\x1f in argv" 1 "$status"; then fails_here=1; fi
status=0
gh_stub_response 0 0 api ok </dev/null 2>/dev/null || status=$?
if ! check_eq "helper rejects index 0" 1 "$status"; then fails_here=1; fi
status=0
gh_stub_response 1 300 api ok </dev/null 2>/dev/null || status=$?
if ! check_eq "helper rejects an exit status above 255" 1 "$status"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 5: the counter counts invocations, not lines of argv ------------
# A real argv may legitimately carry a newline — the GraphQL query that
# list-unresolved-threads.sh passes as `-f query='...'` spans many lines. If the
# call index were derived by counting lines in the log of past argvs, one such
# call would advance the index by as many lines as it spans, and from then on an
# exact-index entry would answer a different call than the one it was written
# for: the poll-loop tests would silently stub the wrong iteration.
total=$((total + 1))
stub_dir_new
fails_here=0
gh api "$(printf 'first\nsecond')" >/dev/null 2>&1 || true
if ! check_eq "counter: a multi-line argv counts as one call" 1 "$(gh_call_count)"; then fails_here=1; fi
gh api plain >/dev/null 2>&1 || true
if ! check_eq "counter: the next call is index 2" 2 "$(gh_call_count)"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 6: an argv spanning lines can be stubbed and matched exactly ----
# The GraphQL query list-unresolved-threads.sh passes as `-f query='...'` spans
# 23 lines. Refusing it would leave that script untestable; matching it loosely
# would let a different query be served this case's body.
total=$((total + 1))
stub_dir_new
fails_here=0
multi="$(printf 'query {\n  field\n}')"
other="$(printf 'query {\n  other\n}')"
# `*` rather than index 1, so the near-miss probe below can only fail on the
# argv. With an exact index it would fail for want of an entry at index 2
# whatever argv it carried, and would prove nothing about matching.
#
# The status is captured rather than left to `set -e`. This file runs under
# `set -euo pipefail`, and until the fix below lands the helper refuses this
# argv — an unguarded call would abort the whole file right here, so the run
# would report nothing about which property failed. Capturing it also makes
# "a multi-line argv can be stubbed at all" an assertion in its own right,
# which is the property being added.
status=0
gh_stub_response '*' 0 api graphql -f "query=${multi}" <<<'matched' || status=$?
if ! check_eq "multi-line argv: stubbable" 0 "$status"; then fails_here=1; fi
if ! check_eq "multi-line argv: matched" 'matched' \
  "$(gh api graphql -f "query=${multi}")"; then fails_here=1; fi
if ! check_no_violations "multi-line argv: no violations"; then fails_here=1; fi
status=0
gh api graphql -f "query=${other}" >/dev/null 2>&1 || status=$?
if ! check_eq "a different multi-line argv is not matched" 99 "$status"; then fails_here=1; fi
if check_no_violations "multi-line argv: probe" >/dev/null 2>&1; then
  echo "FAIL multi-line argv: a near-miss argv recorded no violation"
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 7: --jq is applied to a successful body, never to a failing one -
# Real `gh` filters a 200 through --jq and prints an error body verbatim
# (measured: a 200 carrying `errors` and a 401 both reach stdout raw, and
# `jq -r -c -S` reproduces gh's --jq byte for byte — `-S` because gh filters with
# gojq, which sorts object keys where jq keeps input order). Fixtures are raw API
# bodies and the filter under test really runs. Getting this backwards would
# filter every error fixture down to nothing, and the error cases would assert
# emptiness where reality has a body.
total=$((total + 1))
stub_dir_new
fails_here=0
gh_stub_raw_response 1 0 api graphql --jq '.items[] | select(.keep == true)' \
  <<<'{"items":[{"keep":false,"n":1},{"keep":true,"n":2}]}'
gh_stub_raw_response 2 1 api graphql --jq '.items[] | select(.keep == true)' \
  <<<'{"errors":[{"message":"nope"}]}'
if ! check_eq "--jq filters a successful body" '{"keep":true,"n":2}' \
  "$(gh api graphql --jq '.items[] | select(.keep == true)')"; then fails_here=1; fi
status=0
out="$(gh api graphql --jq '.items[] | select(.keep == true)')" || status=$?
if ! check_eq "a failing body is printed raw" '{"errors":[{"message":"nope"}]}' "$out"; then fails_here=1; fi
if ! check_eq "a failing body keeps its exit status" 1 "$status"; then fails_here=1; fi
if ! check_no_violations "--jq: no violations"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 8: one --paginate invocation serves a page sequence ------------
# gh pages internally, so a script that calls it once still sees several pages'
# output concatenated. Modelling that with one response per invocation would
# make "page 1 arrived, page 2 failed" inexpressible — and that is the state in
# which stdout is non-empty while the listing is incomplete.
total=$((total + 1))
stub_dir_new
fails_here=0
gh_stub_raw_response 1 0 api graphql --paginate --jq '.n' <<<'{"n":1}'
gh_stub_raw_response 2 0 api graphql --paginate --jq '.n' <<<'{"n":2}'
run_sut gh api graphql --paginate --jq '.n'
if ! check_bytes "paginate: both pages, in order" '1\n2\n'; then fails_here=1; fi
if ! check_eq "paginate: exit" 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq "paginate: pages served" 2 "$(gh_call_count)"; then fails_here=1; fi
if ! check_no_violations "paginate: no violations"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# A failure on page 2 keeps page 1's output and hands back the failing status:
# non-empty stdout with a non-zero exit is precisely "you did not see all of
# it", and a caller reading emptiness alone cannot tell this from success.
total=$((total + 1))
stub_dir_new
fails_here=0
gh_stub_raw_response 1 0 api graphql --paginate --jq '.n' <<<'{"n":1}'
gh_stub_raw_response 2 1 api graphql --paginate --jq '.n' <<<'{"errors":[{"message":"boom"}]}'
run_sut gh api graphql --paginate --jq '.n'
if ! check_bytes "paginate: page 1 then the raw error body" \
  '1\n{"errors":[{"message":"boom"}]}\n'; then fails_here=1; fi
if ! check_eq "paginate: failing exit propagates" 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq "paginate: pages served before the failure" 2 "$(gh_call_count)"; then fails_here=1; fi
if ! check_no_violations "paginate: no violations after a mid-page failure"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# A `*` entry answers one page and stops. It matches every index, so continuing
# would loop forever; a multi-page sequence needs explicit indices.
total=$((total + 1))
stub_dir_new
fails_here=0
gh_stub_response '*' 0 api graphql --paginate <<<'only'
run_sut gh api graphql --paginate
if ! check_bytes "paginate: a wildcard entry serves one page" 'only\n'; then fails_here=1; fi
if ! check_eq "paginate: wildcard exit" 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq "paginate: wildcard pages served" 1 "$(gh_call_count)"; then fails_here=1; fi
# An unstubbed paginated argv is still a violation on its first page, not a
# quietly empty listing.
stub_dir_new
status=0
gh api graphql --paginate -f nothing=stubbed >/dev/null 2>&1 || status=$?
if ! check_eq "paginate: unstubbed first page fails" 99 "$status"; then fails_here=1; fi
if ! check_eq "paginate: the unstubbed call is counted" 1 "$(gh_call_count)"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 9: a --jq failure on a stubbed status-0 body exits 99, loudly ---
# `serve()` treats a jq failure on a successful body as a broken fixture or a
# broken filter — a test-authoring error — not as a modelled `gh` behaviour: it
# records a violation and exits 99 rather than degrading into gh's ordinary
# exit 1. "gh received garbage" is modelled separately, by stubbing a non-zero
# status with a raw body (property 7). Iterating a number is a filter no body
# can satisfy, so `.n[]` against `{"n":1}` reproduces the failure on demand.
# stderr is discarded on the probe call, as the surrounding properties do,
# because the stub lets jq's own error text through and a clean test run must
# not print it.
total=$((total + 1))
stub_dir_new
fails_here=0
gh_stub_raw_response 1 0 api graphql --jq '.n[]' <<<'{"n":1}'
status=0
gh api graphql --jq '.n[]' >/dev/null 2>/dev/null || status=$?
if ! check_eq "jq failure: exit 99, not gh's ordinary 1 nor a silent 0" 99 "$status"; then
  fails_here=1
fi
if check_no_violations "jq failure: probe" >/dev/null 2>&1; then
  echo "FAIL jq failure: no violation was recorded"
  fails_here=1
fi
# The violation text names the --jq failure specifically, which is what tells
# this case apart from the unmatched-argv path (property 1): both exit 99 and
# both record a violation, but only this one's message says --jq failed.
case "$(gh_violations)" in
  *'--jq'*'failed on the stubbed body'*) ;;
  *)
    echo "FAIL jq failure: violation text doesn't name the --jq failure: $(gh_violations)"
    fails_here=1
    ;;
esac
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 10: an unreadable expectation is named, not charged to the SUT --
# A mistyped golden path makes `cat` fail, which leaves the want file empty, and
# a byte comparison then reports "stdout differs, want: <nothing>" — the test's
# own mistake billed to the script under test. That is this suite's defect
# class 1 turned inward, so the helper names the path instead of comparing
# against whatever it managed to read.
#
# The probe runs in a subshell because the other half of the same guard is an
# abort: measured, `set -e` is suppressed inside a function invoked in an `if`
# condition — which is how every call site spells it today — but not when the
# helper is called plainly, and then an unguarded `cat` takes the whole file
# down. The subshell keeps a regression to that behaviour reportable here
# instead of ending the run.
total=$((total + 1))
stub_dir_new
fails_here=0
probe_status=0
probe_out="$( (check_stdout_files 'probe' "${HARNESS_TMP}/no-such-expected") 2>&1 )" || probe_status=$?
if ! check_eq "unreadable expectation: status" 1 "$probe_status"; then fails_here=1; fi
# The message is asserted, not just the status: an unguarded `cat` also ends up
# non-zero, so status alone cannot tell the guard from its absence.
case "$probe_out" in
  *'cannot read the expected bytes'*'no-such-expected'*) ;;
  *)
    printf 'FAIL unreadable expectation: message did not name the path: [%s]\n' "$probe_out"
    fails_here=1
    ;;
esac
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- property 11: an `--input -` call's payload is recorded --------------------
total=$((total + 1))
stub_dir_new
gh_stub_response 1 0 api --method POST "repos/acme/widgets/issues/7/comments" --input - <<<'{"id":1}'
printf '%s' '{"body":"a `b` c\n"}' >"${HARNESS_TMP}/want.payload"
gh api --method POST "repos/acme/widgets/issues/7/comments" --input - \
  <"${HARNESS_TMP}/want.payload" >/dev/null
fails_here=0
if ! check_gh_stdin "stdin payload: recorded" 1 "${HARNESS_TMP}/want.payload"; then fails_here=1; fi
# A call with no --input reads nothing, so "no payload" must be its own failure
# rather than a comparison against an empty file, which would pass. The message
# is asserted, not just the return code, following property 10's pattern: `cmp
# -s` against a nonexistent $got already returns non-zero on its own, so a
# check_gh_stdin whose `[ ! -f "$got" ]` branch was deleted — collapsing "gh
# read no payload" into an undifferentiated "the bytes differ" — would still
# pass a status-only assertion here.
stub_dir_new
gh_stub_response 1 0 api "repos/acme/widgets" </dev/null
gh api "repos/acme/widgets" >/dev/null
probe_status=0
probe_out="$( (check_gh_stdin "stdin payload: probe" 1 "${HARNESS_TMP}/want.payload") 2>&1 )" || probe_status=$?
if ! check_eq "stdin payload: probe status" 1 "$probe_status"; then fails_here=1; fi
case "$probe_out" in
  *'gh read no stdin payload for call 1'*) ;;
  *)
    printf 'FAIL stdin payload: probe message did not name the missing payload: [%s]\n' "$probe_out"
    fails_here=1
    ;;
esac
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- gitrepo.sh: a repo with the requested remote URL, branches and commits ---
total=$((total + 1))
gr_fails=0
gr_bare="$(git_repo_bare acme widgets)"
gr_seed="$(git_repo_scratch seed)"
git_repo_init "$gr_seed" main
git_repo_commit "$gr_seed" README.md 'common\n' 'base'
git_repo_checkout "$gr_seed" feature main
git_repo_commit "$gr_seed" FEATURE.md 'f\n' 'feature work'
git_repo_push "$gr_seed" "$gr_bare" main feature
gr_work="$(git_repo_scratch work)"
git_repo_init "$gr_work" main
git_repo_remote "$gr_work" origin "$gr_bare"

if ! check_eq 'gitrepo: bare path encodes owner/repo' \
  'acme/widgets.git' "$(basename "$(dirname "$gr_bare")")/$(basename "$gr_bare")"; then gr_fails=1; fi
if ! check_eq 'gitrepo: remote url is the one set' \
  "$gr_bare" "$(git -C "$gr_work" remote get-url origin)"; then gr_fails=1; fi
if ! check_eq 'gitrepo: branches reached the remote' \
  'feature main' "$(git -C "$gr_bare" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' ' | sed 's/ $//')"; then gr_fails=1; fi
if ! check_eq 'gitrepo: commit message is the one given' \
  'base' "$(git -C "$gr_bare" log -1 --format=%s main)"; then gr_fails=1; fi
if ! check_eq 'gitrepo: file content is the one given' \
  'common' "$(git -C "$gr_bare" show main:README.md)"; then gr_fails=1; fi
if [ "$gr_fails" -ne 0 ]; then failed=$((failed + 1)); fi

# --- gitrepo.sh: a name that would walk the rm -rf out of its own subtree ---
#
# The victim sits one level up, inside $HARNESS_TMP, rather than beside it:
# that is enough to prove the traversal is refused, while never aiming an
# `rm -rf` anywhere a regression could do damage outside the harness's own
# temp dir. The surviving-file check is the load-bearing half — an exit-status
# check alone would still pass if the guard ever moved below the `rm -rf` it
# exists to prevent. It asserts a *file* specifically, because the unguarded
# path deletes the file and then recreates the name as a directory, which an
# existence test would read as untouched.
total=$((total + 1))
gr_guard_fails=0
: >"${HARNESS_TMP}/victim"
gr_status=0
(git_repo_scratch '../victim') >/dev/null 2>&1 || gr_status=$?
if ! check_eq 'gitrepo: traversing name is refused' '1' "$gr_status"; then gr_guard_fails=1; fi
if ! check_eq 'gitrepo: traversing name deleted nothing' 'yes' \
  "$([ -f "${HARNESS_TMP}/victim" ] && echo yes || echo no)"; then gr_guard_fails=1; fi
if [ "$gr_guard_fails" -ne 0 ]; then failed=$((failed + 1)); fi

# --- the sleep stub: counted, and it does not spend wall clock ---
#
# Last in the file deliberately: stub_sleep_instant rewrites PATH for whatever
# follows it, so nothing should.
total=$((total + 1))
sl_fails=0
stub_sleep_instant
stub_dir_new
sl_before="$SECONDS"
sleep 3
sleep 3
sl_elapsed=$((SECONDS - sl_before))
if ! check_eq 'sleep stub: calls counted' '2' "$(sleep_call_count)"; then sl_fails=1; fi
if [ "$sl_elapsed" -ge 2 ]; then
  printf 'FAIL sleep stub: two 3s sleeps took %ss of wall clock\n' "$sl_elapsed"
  sl_fails=1
fi
if ! check_eq 'sleep stub: resolves to the stub' \
  "${HARNESS_LIB_DIR}/bin-nosleep/sleep" "$(command -v sleep)"; then sl_fails=1; fi
if [ "$sl_fails" -ne 0 ]; then failed=$((failed + 1)); fi

# --- gitrepo.sh: git cannot leave the machine, whatever URL it is handed ---
#
# This is the guarantee that makes it safe to let a script under test run a
# real `git push`. Convention is not enough: `retarget-pr.sh` pushes to
# whatever `origin` says, and a test that mis-wired a remote would otherwise
# push to a real repository. GIT_ALLOW_PROTOCOL (exported by gitrepo.sh) makes
# git itself refuse every network transport before it opens a socket, so the
# guarantee holds even for a URL no test author looked at.
#
# The URL points at 127.0.0.1:1 rather than a real host so that a *regression*
# — the guard being dropped — fails against a closed local port instead of
# reaching out over the network. The assertion is on the message, not just the
# non-zero status, because "connection refused" is also non-zero and would let
# a dropped guard pass.
#
# The ssh probe is written `ssh://…:1/` rather than in scp-like form
# (`git@127.0.0.1:path`), which carries no port and so resolves to 22. Measured
# on a machine running a local sshd: with the guard dropped, the scp-like form
# reaches that sshd, and under a tty it blocks on an interactive host-key
# prompt until killed rather than failing. The explicit form keeps all three
# probes on a port nothing listens on, so the regression this row exists to
# catch fails fast instead of hanging.
total=$((total + 1))
proto_fails=0
proto_repo="$(git_repo_scratch proto)"
git_repo_init "$proto_repo" main
git_repo_commit "$proto_repo" README.md 'x\n' 'only commit'
for proto_url in 'https://127.0.0.1:1/acme/widgets.git' \
  'ssh://git@127.0.0.1:1/acme/widgets.git' 'git://127.0.0.1:1/acme/widgets.git'; do
  git_repo_remote "$proto_repo" origin "$proto_url"
  proto_out="$(git -C "$proto_repo" push origin 'refs/heads/main:refs/heads/main' 2>&1)" && proto_status=0 || proto_status=$?
  if ! check_eq "gitrepo: ${proto_url} push is refused" '128' "$proto_status"; then proto_fails=1; fi
  case "$proto_out" in
    *"not allowed"*) ;;
    *)
      printf 'FAIL gitrepo: %s was refused for the wrong reason: %s\n' \
        "$proto_url" "$(printf '%s' "$proto_out" | head -1)"
      proto_fails=1
      ;;
  esac
done
if [ "$proto_fails" -ne 0 ]; then failed=$((failed + 1)); fi

# --- gitrepo.sh: a clone of a local bare remote can be pushed to ------------
total=$((total + 1))
clone_fails=0
clone_bare="$(git_repo_bare acme pushable)"
clone_seed="$(git_repo_scratch pushable-seed)"
git_repo_init "$clone_seed" main
git_repo_commit "$clone_seed" README.md 'common\n' 'base'
git_repo_push "$clone_seed" "$clone_bare" main
clone_work="$(git_repo_clone pushable-work "$clone_bare" main)"
if ! check_eq 'gitrepo: clone checked out the requested branch' \
  'main' "$(git -C "$clone_work" rev-parse --abbrev-ref HEAD)"; then clone_fails=1; fi
if ! check_eq 'gitrepo: clone origin is the bare repo' \
  "$clone_bare" "$(git -C "$clone_work" remote get-url origin)"; then clone_fails=1; fi
git_repo_commit "$clone_work" README.md 'changed\n' 'a change to push'
clone_status=0
git -C "$clone_work" push -q origin 'refs/heads/main:refs/heads/main' 2>/dev/null || clone_status=$?
if ! check_eq 'gitrepo: pushing to the local bare remote succeeds' '0' "$clone_status"; then clone_fails=1; fi
if ! check_eq 'gitrepo: the bare repo received the commit' \
  'a change to push' "$(git -C "$clone_bare" log -1 --format=%s main)"; then clone_fails=1; fi
if [ "$clone_fails" -ne 0 ]; then failed=$((failed + 1)); fi

# --- gitrepo.sh: a push can be made to fail, and then to succeed again -------
#
# A push that fails while everything around it works is the state #170 was
# about, and there is no way to reach it with a correctly configured remote.
# The hook is the only lever that produces it without breaking anything else,
# so that a *later* run in the same repository can then succeed.
total=$((total + 1))
deny_fails=0
git_repo_commit "$clone_work" README.md 'denied\n' 'a change the hook rejects'
deny_before="$(git -C "$clone_bare" rev-parse refs/heads/main)"
git_repo_deny_push "$clone_bare"
deny_status=0
git -C "$clone_work" push -q origin 'refs/heads/main:refs/heads/main' 2>/dev/null || deny_status=$?
if [ "$deny_status" -eq 0 ]; then
  echo 'FAIL gitrepo: the push succeeded while the deny hook was installed'
  deny_fails=1
fi
if ! check_eq 'gitrepo: a denied push moved nothing' \
  "$deny_before" "$(git -C "$clone_bare" rev-parse refs/heads/main)"; then deny_fails=1; fi
git_repo_allow_push "$clone_bare"
deny_status=0
git -C "$clone_work" push -q origin 'refs/heads/main:refs/heads/main' 2>/dev/null || deny_status=$?
if ! check_eq 'gitrepo: the push succeeds once the hook is removed' '0' "$deny_status"; then deny_fails=1; fi
if ! check_eq 'gitrepo: the bare repo caught up' \
  'a change the hook rejects' "$(git -C "$clone_bare" log -1 --format=%s main)"; then deny_fails=1; fi
if [ "$deny_fails" -ne 0 ]; then failed=$((failed + 1)); fi

# --- gitrepo.sh: a ref that points at a blob rather than a commit ------------
#
# retarget-pr.sh's ancestor gate has a third branch for `git merge-base
# --is-ancestor` failing for a reason of its own, rather than returning either
# verdict. A ref pointing at a non-commit is how that is reachable with real
# git and no stub: the fetch succeeds, FETCH_HEAD is a blob, and the ancestor
# check exits 128.
total=$((total + 1))
blob_fails=0
git_repo_blob_ref "$clone_bare" blobref 'not a commit\n'
git -C "$clone_work" fetch -q origin -- blobref
blob_sha="$(git -C "$clone_work" rev-parse FETCH_HEAD)"
if ! check_eq 'gitrepo: the fetched ref is a blob' \
  'blob' "$(git -C "$clone_work" cat-file -t "$blob_sha")"; then blob_fails=1; fi
git -C "$clone_work" fetch -q origin -- main
blob_status=0
git -C "$clone_work" merge-base --is-ancestor "$blob_sha" "$(git -C "$clone_work" rev-parse FETCH_HEAD)" 2>/dev/null || blob_status=$?
if ! check_eq 'gitrepo: is-ancestor on a blob is neither verdict' '128' "$blob_status"; then blob_fails=1; fi
if [ "$blob_fails" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
