# gh mechanics

This file holds the reasons behind `pr-to-ready`'s `gh` invocations, and behind the local commands that back them up — why a particular command is used over the obvious alternative, and why its result is tested the way it is.

Every trap below has the same shape: **stdout alone never separates a `gh` failure from a genuine negative.** Auth, network, and repo-context failures print nothing and exit non-zero; a genuine negative exits 0 and prints either nothing or an empty structure such as `[]`, depending on the command. So neither an empty stdout nor a non-empty one settles which you are looking at — only reading it together with the exit status does. Collapsing the two is how a run opens a second PR, drives the wrong one, or reports a reviewer as unavailable when the request was merely never read back.

## Asking whether a PR exists — `gh pr list`, not `gh pr view`

`gh pr view` reads a selector made entirely of digits as a PR *number*, so a branch literally named `123` would resolve PR #123 instead of that branch's own PR. `gh pr list --head` is a literal branch-name filter with no such ambiguity, and it already returns everything the check needs.

The result takes **output and exit status together**. Exit 0 with `[]` is the only thing that means "no PR". A non-zero exit does not mean there is none: the failures above print nothing on stdout and look exactly like absence, and the message wording varies by `gh` version, so neither signal alone can be keyed off. A non-zero exit is "couldn't tell" — and opening a second PR on top of one you couldn't see is worse than stopping.

## Reading the PR number back — `.[]`, never `.[0]`

Print every match and count the lines. Two things go wrong with indexing:

- A branch can carry more than one open PR, since a second PR may target a different base. `.[0]` would pick one of them arbitrarily and hand every later step the wrong `<PR>`.
- On a branch with no PR at all, `.[0]` is `null`, which jq interpolates as text — printing `PR=null draft=null`. That is non-empty output, so it would bind `<PR>` to a string rather than reading as absence.

`.[]` yields nothing for an empty list and one line per match, so the line count answers both questions at once. That is what makes the four outcomes in `SKILL.md` distinguishable from each other.

## Requesting Copilot — the flag and the REST form are alternatives

`gh pr edit --add-reviewer "@copilot"` and the `requested_reviewers` REST endpoint request the same thing two ways. They are alternatives rather than a sequence: running both unconditionally posts a needless request.

**Neither can be judged by its exit status, and they must not be chained with `||`.** The flag can exit 0 and print the PR URL while adding nobody, so a `||` fallback never fires — and the behaviour is intermittent, so one success proves nothing about the next run. Only a readback settles it, which is why the REST form runs just when the flag didn't take.

**That readback reads the issue timeline's `review_requested` events, and never the PR's requested reviewers.** Copilot is a Bot — the event carries `"login": "Copilot"` with `"type": "Bot"` and a `BOT_…` node id — while `GET /repos/{owner}/{repo}/pulls/{n}/requested_reviewers` reports only `users` and `teams`, so Copilot appears in neither. Measured: read one second after a request GitHub had already recorded, 37 seconds before `copilot_work_started` and 76 before the review arrived, it returned `{"users":[],"teams":[]}`; across every PR here carrying a Copilot review it was never once non-empty. Keyed on that endpoint, the request script reported Copilot permanently unavailable on every run while itself successfully requesting the review each time. `gh pr view --json reviewRequests` is untested against a Bot reviewer and is no safer a guess.

The timeline count is compared against one taken **before** the request, for the same reason the review baseline below is: a previous round's `review_requested` event is still there, so an absolute count reads as success with nothing having landed. Copilot counts as unavailable only when nothing landed after the REST form — and failing to *read* the timeline is not the same as nothing having landed, which is why that case stops the run instead of reporting unavailable.

## Identifying a bot — match the login, not the timestamp

Bot logins differ across surfaces: Copilot appears both as `Copilot` and as `copilot-pull-request-reviewer[bot]`. Matching a substring of the author login covers the variants. Attributing by timestamp instead misreads a human who happened to comment in the same window as the reviewer.

## Mergeability — `mergeable`, never `mergeStateStatus`

`gh pr view --json` offers both, and only one of them can be branched on.

**`mergeStateStatus` varies with the caller's push permission**, so it describes the reader as much as the PR. Across `cli/cli`'s eight open PRs, draft and non-draft alike, it came back `BLOCKED` on every one while `mergeable` returned `MERGEABLE` for those same PRs. A gate keyed on it would therefore stop every PR, for a reason having nothing to do with the branch. Record it as context in a report if it helps; never decide anything with it.

Its `BEHIND` value is no better as a trigger for taking the base in, and for a second reason on top of that one: sitting behind the base is the ordinary condition of a branch rather than a defect, so gating on it would hold up PRs with nothing wrong. What actually warrants taking the base in is *the prerequisite having merged*, which is a different question altogether.

## Why `mergeable` gets a bounded re-read, and what backs it up

`mergeable` has three values, and `UNKNOWN` is not one of the answers — GitHub computes mergeability lazily, so it means "not worked out yet". Reading it as either verdict is wrong, which is why it is re-read rather than settled on the spot.

That re-read is bounded by a clock, and a small one. The bound has nothing in common with waiting on a reviewer: the computation is a background job that finishes in seconds, so anything near 2-2's review wait would leave the run idle for no reason.

**`git merge-tree` sits after `mergeable`, not in place of it.** It is permission-independent and answers at once with no polling, which is what a last rung wants — but the question being asked is what GitHub's merge button will say, and `mergeable` is the authority on that. So the local check settles what GitHub was too slow to settle, instead of pre-empting it.

**Resolve both refs before reading `merge-tree`'s exit status.** It exits 1 for a genuine conflict *and* for a ref that fails to resolve — measured on git 2.43.0, where a nonexistent ref produced exit 1 exactly as a real conflict did, the two separated only by a message on stderr. Read on its own, that exit status turns a mistyped or never-fetched ref into a reported conflict, halting the run over something that was never wrong with the branch at all. Resolving each tip through `git rev-parse --verify --quiet` first removes that case before the exit status is read.

**Capture the two tips as shas, one per fetch.** `git fetch` rewrites `FETCH_HEAD` on every call, so fetching the base and then the branch leaves `FETCH_HEAD` holding only the second of them. Passing it as both arguments would compare the branch with itself and find no conflict — a clean answer to a question nobody asked.

## Recording the Copilot baseline — before the request, not after

An id-based baseline taken after the request can already contain the very review being waited for, so the wait returns immediately — the loop then judges an older diff's feedback and reaches "clean" with no reviewer having actually seen the current push. The comparison has to be against that pre-request baseline, not against the set of comments the run has already handled: an unhandled id also matches a review that predates the run entirely, so "unhandled" alone can't stand in for "post-request".
