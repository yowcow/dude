# tests/

An offline test suite for the `gh`-wrapping scripts under `skills/*/scripts/`.
The tree sits beside the skills it tests, but **not inside any skill
directory**: what this repository distributes as a plugin is `skills/` and its
contents, so a `tests/` dir inside a skill would ship to every agent that
installs the plugin. `tests/` at the repository root ships to none of them.

## Layout

- `tests/run.sh` — the runner.
- `tests/lib/harness.sh` — sourced by every test file: sets up `PATH`, hands
  out stub directories, runs the script under test, and provides the
  assertion helpers.
- `tests/lib/bin/gh` — the fake `gh`. `harness.sh` puts it first on `PATH`,
  so any script under test that calls `gh` reaches this stub, never the network.
- `tests/lib/gitrepo.sh` — builders for disposable real git repositories,
  for the scripts that shell out to `git`. Sourced after `harness.sh`.
- `tests/lib/bin-nosleep/sleep` — the instant `sleep`, put on `PATH` only by
  an explicit `stub_sleep_instant` call.
- `tests/scripts-have-tests.sh` — the coverage gate: every script under
  `skills/*/scripts/` must have a test file, or a line in the allowlist
  beside it. Not named `*_test.sh`, so `run.sh` does not collect it directly;
  `scripts-have-tests_test.sh` is what runs it.
- `tests/scripts-have-tests.allowlist` — the scripts exempted from that gate,
  one repo-root-relative path per line.
- `tests/lib/harness_test.sh` — a self-test of the harness mechanism itself
  (no script under test).
- `<name>_test.sh` anywhere under `tests/` — the actual test cases.

## Running

- `tests/run.sh` — runs every `*_test.sh` under `tests/`, each in its own
  `bash` process so one file's failure can't infect another, and reports how
  many files failed. Discovery uses `find`, not bash 4's `globstar`, because the
  scripts under test are kept running on bash 3.2 and a degraded `**` would
  silently match only one nesting depth.
- `tests/run.sh <file> [<file> ...]` — runs only the named file(s).

## Writing a table-test case

Each row typically does:

1. `stub_dir_new` — fresh stub directory; resets the call counter and manifest.
2. One or more `gh_stub_response <index|*> <exit-status> <argv...>` calls
   (body on stdin) to script what `gh` should answer — or
   `gh_stub_raw_response`, where the call's own `--jq` is what the case is
   testing. The next section says which to reach for.
3. `run_sut <cmd...>` — runs the script under test with stdin `/dev/null`,
   capturing stdout/stderr to `$SUT_STDOUT`/`$SUT_STDERR` and status to
   `$SUT_STATUS`.
4. Assertions: `check_eq`, `check_bytes`, `check_no_violations`, `check_gh_stdin`,
   plus a check on `$SUT_STATUS`.

## The `gh_stub_response` / `gh_stub_raw_response` contract

`gh_stub_response <index> <exit-status> <argv...>` (body from stdin). `<index>`
is a positive integer — the global call number within the stub dir that this
entry answers — or `*`, meaning "any call not otherwise matched exactly." An
exact index wins over `*`. An `<argv>` element containing `\x1f` is rejected:
that byte joins the elements, so `["a\x1fb"]` and `["a","b"]` would be
indistinguishable and one case's body would be served to the other. Tabs and
newlines are fine — the joined argv lives in a file of its own (`argv.N`)
rather than a field of the TSV manifest, because real argvs span lines: the
`--jq` filter `list-copilot-reviews.sh` passes is one three-line argument, and
the GraphQL query `list-unresolved-threads.sh` passes as `-f query='...'` spans
23 lines. Either is matched on its exact bytes, by `cmp` on two files. A
malformed index or an exit status outside 0-255 is rejected too.

**`gh_stub_response` versus `gh_stub_raw_response`** — same signature, and they
differ only in what the body on stdin is:

- `gh_stub_response` — the body is gh's **stdout**, already filtered if the call
  carries `--jq`. The stub hands it back verbatim. Use this by default: most
  cases hold the script under test to an output contract, and the fixture states
  that contract directly.
- `gh_stub_raw_response` — the body is the raw **response gh received**, and the
  stub applies the call's own `--jq` to it (with `-S`, since gh filters through
  gojq, which sorts object keys where jq keeps input order). Use it when the
  filter is part of what is under test: `list-unresolved-threads.sh`'s
  `select(.isResolved == false)` lives in the script, so a pre-filtered fixture
  would decide the very answer the test is checking, and "zero unresolved
  threads" would assert nothing.

The distinction is explicit rather than inferred because the stub cannot tell
the two kinds of body apart by looking, and each wrong guess fails in a
different direction: a filter applied to an already-filtered body errors out,
while a filter skipped on a raw body silently hands the caller the whole
document as though it had been selected from.

For an argv carrying `--paginate`, successive indices are the **pages of one
invocation**: gh pages internally, so a script that calls it once still sees
every page's output concatenated. The stub stops at the first of — no entry for
the next index (the scripted pages ran out, which is how a real run ends), a
non-zero status (it exits with that status, the pages already served still on
stdout), or an entry matched via `*` (which matches every index and would
repeat forever, so it answers one page). `gh_call_count` therefore counts
responses served: invocations for an ordinary call, pages for a paginated one.

## Real git: `tests/lib/gitrepo.sh`

Scripts that shell out to `git` are tested against **real repositories**, not a
git stub: they lean on behaviour a stub would only encode an opinion about —
`FETCH_HEAD` being overwritten by each fetch, `git merge-tree` exiting 1 for a
genuine conflict and an unresolvable ref alike. Source `gitrepo.sh` after
`harness.sh`; everything it builds lives under `$HARNESS_TMP` and is removed
with it.

- `git_repo_bare <owner> <repo>` — a new bare repo at
  `$HARNESS_TMP/remotes/<owner>/<repo>.git`; prints the path. The **path is the
  identity**: `check-pr-state.sh` reduces a remote URL to its last two
  segments, so this repo reads as `<owner>/<repo>` while still being a local
  directory `git fetch` can reach offline.
- `git_repo_scratch <name>` — a fresh empty directory; prints the path.
- `git_repo_init <dir> <initial-branch>` — an empty non-bare repo with `HEAD`
  on that branch.
- `git_repo_commit <dir> <file> <content> <message>` — `<content>` goes
  through `printf '%b'`, so `\n` works.
- `git_repo_checkout <dir> <branch> [<start-point>]` — with a start point it
  creates the branch there.
- `git_repo_remote <dir> <name> <url>` / `git_repo_push <dir> <remote> <refspec>...`
- `git_repo_clone <name> <url> <branch>` — a work repo cloned from `<url>` with
  `<branch>` checked out and `origin` pointing back at it; prints the path. A
  real clone rather than init + remote add, so a script under test finds the
  remote-tracking refs and fetch refspec a real checkout has.
- `git_repo_origin_head <dir> <branch>` — points `refs/remotes/origin/HEAD` at
  that branch, which a real clone has and a `git init` + `git remote add` pair
  does not. No default-branch ladder reads that symref any more; callers plant
  it either to reproduce that real-clone state for realism, or to prove a
  stale or wrong value here is ignored — the proving kind names a branch that
  exists on the remote and is the wrong answer, which is the shape the removed
  rung got wrong. A row wanting "the default branch is named but absent from
  the remote" builds it by stubbing `gh repo view` with that name, not here.
- `git_repo_merge <dir> <ref>` — merges `<ref>` into `<dir>`'s current branch
  with the same fixed clock `git_repo_commit` uses.
- `git_repo_deny_push <bare>` / `git_repo_allow_push <bare>` — install and
  remove a `pre-receive` hook that rejects every push. This is the only way to
  reach "the merge landed locally and the push did not", the state #170 was
  about. A hook rather than a mode bit, which a suite running as root ignores.
- `git_repo_blob_ref <bare> <tag> <content>` — points `refs/tags/<tag>` at a
  blob instead of a commit, so a caller can reach `git merge-base
  --is-ancestor`'s error exit (128) rather than either of its verdicts.

`git_repo_scratch` and `git_repo_bare` refuse a name containing `/` or `..`.
Both clear the directory with `rm -rf` before rebuilding it, and a name is a
single path segment by contract, so `..` would aim that rm at a path the
caller never named. `rm` itself only catches the blunt form: POSIX makes it
refuse an operand whose *last* component is `..`, so `../..` is rejected
loudly while `../../x` deletes a sibling of `$HARNESS_TMP` and exits 0 without
printing anything. The guard is for that silent case.

Sourcing the file cuts the developer's own git configuration out of the
picture (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`,
`GIT_TERMINAL_PROMPT=0`, fixed author/committer identity and timestamps). That
is not only determinism: a personal `url.<base>.insteadOf` can rewrite a local
path into a network URL, which would put this suite on the network through a
setting no test can see.

`git push` in this suite cannot reach the network, and not merely because the
remotes happen to be local paths: sourcing `gitrepo.sh` exports
`GIT_ALLOW_PROTOCOL=file`, so git refuses `https`, `ssh` and `git://` at the
transport layer — `fatal: transport 'https' not allowed`, exit 128 — before a
socket is opened, while a local path still fetches and pushes normally.
`harness_test.sh` asserts all three refusals, and asserts them on the message
rather than the exit status alone, since "connection refused" is non-zero too
and would let a dropped guard pass.

## Instant `sleep`: `stub_sleep_instant`

Call `stub_sleep_instant` in a test file whose script under test polls. It puts
`tests/lib/bin-nosleep/` first on `PATH` and asserts the resolution;
`sleep_call_count` then reports how many sleeps happened in the current stub
directory, so a bounded poll is asserted by **count** rather than by wall
clock. `check-pr-state.sh`'s `UNKNOWN` re-read alone is 5 × 3 s per row.

It is opt-in, not always on, so it cannot change the meaning of a test file
written expecting real waits. Unlike the fake `gh`, it accepts any argv: the
`gh` rule exists because an unstubbed call would be answered by the network,
and `sleep` hands the caller nothing it reads.

## The lint selection: `lint.sh`

`lint.sh` selects by shebang, not by a `*.sh` glob, so the extensionless PATH
stub `tests/lib/bin/gh` is checked like anything else. It walks from the
repository root, and prunes three directories that hold checkouts rather than
this repository's own code: `.git`, `.worktrees`, and `.claude/worktrees`.

**A run from inside a linked worktree cannot verify that prune.** There `.git`
is a file rather than a directory and neither worktree directory exists, so
nothing matches and the expression prunes nothing — a wrong expression still
looks green. To exercise it where it bites, build a checkout that has the real
shapes and run the script there:

```bash
probe="$(mktemp -d)"
git clone --quiet --no-hardlinks . "$probe/dude"   # a real .git directory
cp -a tests Makefile .shellcheckrc "$probe/dude/"  # plus anything uncommitted
mkdir -p "$probe/dude/.worktrees/x" "$probe/dude/.claude/worktrees/y"
printf '#!/usr/bin/env bash\nexit 0\n' >"$probe/dude/.worktrees/x/leak.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$probe/dude/.claude/worktrees/y/leak.sh"
"$probe/dude/tests/lint.sh"
```

The selected count must match a run from the working tree, and no path under
any of the three pruned directories may appear in the listing. Dropping any one
name from the prune raises the count, which is what makes the check meaningful;
`.claude` in particular is not gitignored, so nothing else keeps it out.

## The coverage gate: `scripts-have-tests.sh`

Every file under `skills/<skill>/scripts/` must have a non-empty test file at
`tests/<skill>/<name>_test.sh`, or a line naming it in
`tests/scripts-have-tests.allowlist`. `scripts-have-tests_test.sh` runs the
gate against the real tree as its first two cases, which is how the gate reaches
`make test` with no Makefile or workflow change — the same trick `lint.sh`
uses to land in its own selection.

The gate is **permanent**. An allowlist with no entries — including the state
where only the header comments remain — and an absent allowlist file both mean
"no exemptions", and both are success. Nothing about finishing the coverage work
asks for the gate to be removed.

Its rules, each of which `scripts-have-tests_test.sh` asserts against a synthetic
tree rather than stating as prose:

- An entry naming a script that no longer exists is an **error**: an exemption
  must not outlive its script, or a rename leaves the new name unchecked.
- An entry for a script that has since gained a test is **not** an error, only
  unnecessary. Making it one would force a PR that lands a test to also delete a
  line it does not own.
- Comment and blank lines are not entries — neither exemptions nor names to
  check. A comment outlives the entries it was written for.
- An empty enumeration is an **error**. A broken selection and a fully covered
  tree are otherwise the same green.
- An empty test file is **not** coverage. `run.sh` collects it and
  `bash <empty>` exits 0, so it is a passing test with no detection power.
- A `find` that dies partway through `skills` is a **failure**, never a green
  over the part it managed to read.
- Selection is by position in the tree, not by shebang: a script under
  `scripts/` in a language ShellCheck does not cover must not be silently
  exempt as well as unlinted.
- An entry is matched **whole**, never as a substring of the entries joined
  together: two adjacent lines must not be able to combine into an exemption
  neither of them spells. Measured on the first version, which joined them with
  newlines — a script really named `weird\nname.sh` was exempted by the pair
  `skills/alpha/scripts/weird` and `name.sh`, and `no test for` was never
  printed for it. A name carrying a literal newline therefore cannot be exempted
  at all, since `read -r` splits there; it is reported as uncovered, which is the
  safe direction.
- A **dangling symlink** at the allowlist path is "present but unreadable", an
  **error** — not "absent". `-e` follows the link and is false for a dangling
  one, so the existence test answered with a success state and never reached the
  readability refusal. Measured on that version: a dangling link gave `1
  script(s), 1 with tests, 0 exempted` and exit 0. A link that resolves to a
  readable regular file is still read: only this gate reads the allowlist, so
  following it costs nothing.
- A **symlink** under `scripts/` is enumerated like a regular file, which is
  where this parts company with `lint.sh`'s deliberate `-type f`. For a linter
  that exclusion is right; for this gate `-type f` answers the wrong question,
  since it classifies a symlink by the link. Measured: an untested symlink
  beside one covered regular script reported `1 script(s), 1 with tests, 0
  exempted` and exit 0, naming the symlink nowhere. The target is never resolved
  or read — only visibility is at stake — so a dangling link is reported rather
  than fatal.

For RED verification the mutated copy has to live in `tests/`, not under a
bare `mktemp -d`: the gate anchors its default root on its own file location, so
a copy elsewhere resolves the root to that directory's parent and dies on
`find`, which fails cases 0 and 1 with `the tree was not fully read` even when
the copy is unmodified. Same class as the sibling problem above — a
self-anchoring script has to sit where its anchor resolves. `run.sh` collects
only `*_test.sh`, so a `mut.sh` beside the gate is not picked up, but `lint.sh`
selects it by shebang, so remove it when done.

## The mechanism properties (and why they matter)

`tests/lib/harness_test.sh` proves the properties the rest of the suite
depends on:

1. **An unstubbed argv fails the case** rather than passing through to the
   real `gh`. Without this, a missing stub reads as "the test passed" while
   quietly reaching the network — the exact defect this suite exists to catch.
2. **The stub counts calls globally**, so a poll loop can be scripted to
   answer its second call differently from its first.
3. **Stdout is compared byte-for-byte**, not line-by-line — a stray or
   missing trailing newline is invisible to a line-count comparison.
4. **An argv the manifest cannot disambiguate is refused when stubbed**,
   rather than silently never matching: an `\x1f` in a stubbed argv, a
   malformed call index, or an out-of-range exit status fails the helper on
   the spot. It is the *only* thing refused — an argv that spans lines is
   stubbable, which is property 6.
5. **The call index counts invocations, not lines**, so an argument that
   spans lines — a GraphQL query passed as `-f query='...'` — does not
   advance the index past the call a later exact-index entry was written for.
6. **An argv spanning lines is stubbable and matches only itself** — the
   23-line GraphQL query is why, and a near-miss query must still be reported
   as an unstubbed argv rather than served this case's body.
7. **`--jq` is applied to a successful body and never to a failing one** —
   what real `gh` does (measured), for entries registered with
   `gh_stub_raw_response`. That is what lets the filter in the script under
   test really run; an error fixture reaches stdout whole, as a caller would
   see it.
8. **One `--paginate` invocation serves a page sequence, truncating at a
   failing page** — "page 1 arrived, page 2 failed" is the state in which
   stdout is non-empty and the listing is incomplete, and a caller keying on
   emptiness alone cannot tell it from success.
9. **A `--jq` that fails on a successful body is loud** — a violation and
   exit 99, not gh's ordinary exit 1. A body the filter cannot handle is a
   broken fixture or a broken filter, which is a test-authoring fault and has
   to surface as one; "gh received garbage" is modelled by stubbing a non-zero
   status with a raw body instead. Degrading it to exit 1 would make the
   mechanism itself commit the confusion between "absent" and "could not ask"
   that this suite exists to catch.
10. **An expectation the harness cannot read is named, not charged to the
    script under test** — a mistyped golden path leaves the want file empty,
    and a byte comparison would then report "stdout differs, want: nothing",
    blaming the code for the test's own mistake. Defect class 1, pointed
    inward. The same guard keeps a plain (non-`if`) call from aborting the
    whole test file under `set -e`.
11. **The payload of an `--input -` call is recorded, and its absence is its
    own failure** — the three `plan-work` posting scripts pipe their body to
    `gh` on stdin precisely so it never reaches the shell, which puts the body
    outside the argv the stub matches on. Without the payload, `jq -Rs` and
    `jq -R` are indistinguishable: dropping the slurp sends one JSON document
    per line and changes no byte of the argv. `check_gh_stdin` compares those
    bytes, and reports "gh read no stdin payload" separately from "the bytes
    differ", because a script that stopped piping its body would otherwise be
    charged with sending different bytes, and an empty expectation would let it
    pass. Only a call carrying `--input -` has a payload, which is real gh's own
    rule.

## RED verification

To confirm a test actually catches the bug it claims to, point it at the
pre-fix version of the script under test:

```bash
git show <fix>^:<path> >"$tmp/old.sh"
SUT="$tmp/old.sh" tests/run.sh <one-test-file>
```

The specific commits named below, and in the `RED verification` headers of the
test files under `tests/pr-to-ready/`, are from this suite's original home in
`yowcow/dotfiles`. They do not resolve here — this repository started fresh
rather than importing that history — so they record which fix each test was
measured against, not a `git show` runnable in this repository. The recipe
itself works as written against any commit that is in this history.

The same goes for every bare issue number and TODO-item reference anywhere
under `tests/`, wherever it appears: all of them point at that same tracker,
and none at this repository's issues. They read as provenance for a
measurement — which report or item established the behaviour the comment
records — and a reader chasing one wants `yowcow/dotfiles`, not `yowcow/dude`.

A script that shells out to a sibling needs that sibling beside the copy:
`watch-copilot-review.sh` finds `list-copilot-reviews.sh` through
`dirname "$0"`, so a pre-fix copy alone in a temp dir cannot find it, every
listing comes back empty, and rows fail for a reason that has nothing to do
with the defect.

```bash
cp skills/pr-to-ready/scripts/list-copilot-reviews.sh "$tmp/"
```

`SUT` names one script under test in place of a test file's default. `run.sh`
refuses to run more than one test file while `SUT` is set, since it names a
single script and pointing a whole suite at it would apply it to every file. It
also refuses a `SUT` that does not name a readable non-empty file, before
running anything: a missing path makes nearly every row fail, which is the shape
of a successful RED, an unreadable one fails them the same way at exit 126, and
an empty one makes them all pass, which reads as a test with no detection power.

`check-pr-state.sh` → `a548e36^` — the local fallback did not verify that the
working tree's `origin` was the PR's repository (#172).

`resolve-pr-base.sh` → `bb8d8b8^` — the `Base-Branch` trailer scan walked to
root, so a branch that recorded nothing picked up whatever trailer it inherited
from shared history and handed that branch back as `--base` (#171).

`retarget-pr.sh` → `80376f3^` — a matching `baseRefName` was treated as the
whole answer, so a run whose push had failed reported `BASE-OK` on its next
attempt while the remote branch was still the pre-merge one (#170).

`run.sh` → `f2b1e41^` — a `SUT` naming a nonexistent or an empty file was
accepted, and the resulting failures were indistinguishable from a successful
RED verification (#214). Also `f2b1e41` itself, **without** the caret: that
commit is where the guard above landed, and it checked `-f` and `-s` but not
`-r`, so a mode-000 file walked through it and failed every row at exit 126 —
the same false RED, reached by permission rather than absence (#217). No caret,
because `f2b1e41` is where that second defect was left standing rather than
introduced.

`watch-claude-review.sh` → `2bd1745^` — `--limit 20` pushed the target run out
of the listing, so the filter printed `[]` and the caller read the review as
never arriving (#173). Also `e14114a^`, where the workflow search was
cwd-relative: from a subdirectory it reported Claude as unavailable.
