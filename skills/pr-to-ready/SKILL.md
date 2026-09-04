---
name: pr-to-ready
description: Use to take an open PR — given its number or URL — to a PR whose CI passes and whose review is clean, left at ready or draft; it sets up its own workspace, so a fresh session needs nothing but the reference. A branch with no PR on it yet is the fallback entry. Triggers on "take this PR to ready", "drive this PR", a PR URL on its own, "what next after opening the PR", "CI is failing", "run the review loop", "take it out of draft", "handle the review feedback".
---

# pr-to-ready

Take an open PR to a reviewed one: resolve the run from the PR's number or URL, set up the workspace its head branch needs, then loop until CI passes and the review is clean. **The only PR-status change this flow makes is draft → ready**, and it makes that one only when the user asked for it up front and the run came out clean; anywhere else, clean or not, the PR's status is left as it was found. Precondition: a PR whose commits are already verified — normally the draft PR `implement-work` left behind. A branch carrying no PR yet is the fallback entry, and an unpushed one is not a blocker: push it, open the draft PR, and go on. This flow ends at one of three terminal states: ready, draft, or **handed back to a person** when something surfaces that this run cannot resolve on its own.

## Orchestration model

Run this skill as an orchestrator: the main loop owns control flow, every decision, and every state-mutating action. Steps run sequentially, never in parallel, with one exception — evaluating independent review findings, where one subagent per finding is launched together in Step 2.

**Never delegate:** the clean judgment and stop conditions, including reading whether checks pass; any change that touches the worktree, together with committing and pushing it; and any write to the PR itself — comments, thread replies, thread resolution, marking it ready.

**Delegate:** diagnosing *why* a check failed, wherever that comes up — deciding whether checks are green stays above, only the diagnosis of a red one is handed off; collecting reviewer comments into a structured list of findings; and evaluating each finding. Every delegated subagent is read-only and advisory: it investigates and proposes, and the orchestrator is the one that applies a change, commits, and pushes.

**Evaluating a finding never happens in the main loop**, on any round, and goes out at the tier `using-dude`'s **Worker tier** sets for a marked worker. The main loop carries this run's own account of why the code reads as it does — it applied every fix on this branch, and where the run continued from `implement-work` it wrote the branch too — so a verdict reached there is anchored on that account, which is exactly what `review-code`'s **Orchestration model** buys a read-only worker in a fresh context to escape. A real finding rejected on such a verdict is replied to and resolved on it, and no later round reads the thread again.

## Step 0: Set up the run

### 0-1. Ask whether to mark ready on clean

Ask the user: once CI is green and review is clean, should this run mark the PR ready, or leave its status as it is? Record the answer as the **ready-on-clean** flag — fixed for the rest of the run, not re-asked mid-loop. Step 3 branches on it.

### 0-2. Resolve the run from the PR reference

Bind the run from the caller's reference — a PR number or a PR URL. If none was given, ask; **don't guess it from the current checkout**, whose repository need not be the PR's at all.

Call `<skill-dir>/scripts/resolve-pr-entry.sh <pr-ref>` once — `<skill-dir>` being this skill's own directory inside the installed plugin, `skills/pr-to-ready/`. It resolves the reference against the repository the reference itself names, checks that this working tree is a checkout of that repository, and answers on one line. Branch on it:

- `PR <n> branch=<head> base=<base> repo=<owner>/<repo> draft=<bool>` — bind `<PR>`, `<branch>`, and the `<owner>` and `<repo>` every later script call takes; none of those three is re-derived from the checkout again. `<base>` is the base the PR points at **now**, which is not the same question as the base it *should* sit on: Step 1 re-resolves that and may replace it.
- `STOP <slug>` — report the stop and end the run. Nothing downstream has a repository, a branch, or a base it could work from.

**Fallback — a branch with no PR on it yet.** Where the caller gave a branch name instead (work `implement-work` left before its hand-off, a branch cut outside dude, or a PR deliberately skipped), call `<skill-dir>/scripts/ensure-draft-pr.sh <branch> <title> <body-file>` first: it pushes the branch if only a local ref exists, looks for a PR already on it, and creates a draft one when none is found — resolving the base itself, at that point alone. It answers `PR <n> found draft=<bool>`, `PR <n> created draft=true base=<base>`, or `STOP <slug>`. On either `PR` line, feed `<n>` back through `resolve-pr-entry.sh` above so the rest of the run binds from one place; on a `STOP`, report it and end the run. Title and body follow `implement-work`'s **Hand off**, which owns that convention.

### 0-3. Prepare the workspace

`<branch>` need not be checked out here, or exist here at all — a fresh session entered from a PR URL is the ordinary case — and every later step writes to a working tree: Step 1's `retarget-pr.sh` merges the base and pushes it, and Step 1's diagnosis fixes and 2-3's `accept` fixes commit and push. Preparing it once here rather than where each of those needs it keeps one step instead of three.

Call `<skill-dir>/../implement-work/scripts/attach-workspace.sh <branch> <path>` — the sibling skill's script, reached by relative path because this skill holds no copy of it. `<path>` follows `superpowers:using-git-worktrees`'s own directory convention. Branch on the one line it prints:

- `REUSE <path>` — a worktree already carries `<branch>`; use it as-is.
- `ATTACHED <path>` — the branch existed locally or on the remote, and a new workspace now tracks it. Use it.
- `CREATE` — **stop.** A PR's head branch exists on its repository's remote by definition, and 0-2 has already established that this checkout is that repository, so nothing to attach to means the branch was deleted under an open PR. Report it; don't cut a fresh branch, which would put an empty history under the name the PR points at.

**Run every later step from that workspace.** Without this, the run edits, commits and pushes in whatever tree the session started in — with `<branch>` unchecked-out, that is whatever branch was: Step 1's diagnosis fix and 2-3's `accept` fixes are committed onto the default branch and pushed there, reviewed by nobody, while the PR they were written for does not move.

## Step 1: Settle the base, then get CI clean

Before watching CI, settle whether the base is still the right one — the prerequisite's state can have moved since Step 0.

1. Re-resolve it: `<skill-dir>/scripts/resolve-pr-base.sh <branch>` → `BASE <name>` or `STOP <slug>`. This is the base the branch *should* sit on, read from its `Base-Branch:` trailer and the prerequisite's current state — a different question from the `<base>` 0-2 bound, which is the one the PR points at now.
2. Check the PR against that answer: `<skill-dir>/scripts/check-pr-state.sh <owner> <repo> <pr-number> <base>` → `BASE-OK|BASE-DRIFT <current-base> MERGEABLE|CONFLICTING|UNKNOWN`, or `STOP <slug>`. The name it prints is the base the PR points at **now**, not the one you passed in — which is what makes `BASE-DRIFT` worth reading. Read-only: it measures and never fixes.
3. On `BASE-DRIFT`: pull the resolved base in with `<skill-dir>/scripts/retarget-pr.sh <owner> <repo> <pr-number> <branch> <base>` → `BASE-OK <base>` (nothing to do), `RETARGETED <old> <new>` — the merge is pushed, so CI below runs against the new tip rather than the one it already passed on — or `STOP <slug>` on a conflict while merging the new base in.
4. On `CONFLICTING`, or on an `UNKNOWN` that stands after the script's own bounded re-read: neither is something to fix here — both are the **third terminal state**. Stop, and hand the branch back to a person with what was found; don't attempt a resolution, and don't take an undetermined mergeability for a clean one. **Name `implement-work` as where it goes back to**, whose completion gate absorbs the base and re-verifies: with no destination named, the person's only cue is the PR they were already in, so they re-enter `pr-to-ready` and land on this same terminal state again, having changed nothing.

Then watch CI with `<skill-dir>/scripts/watch-checks.sh <owner> <repo> <sha>`, and branch on its **exit status** before reading anything it printed. **Exit 0** prints one line per check, name, status, conclusion, and is the only status whose conclusions are a verdict on anything; whether they pass is read here, never by the script, so every one passing goes to Step 2 and a failing one goes to the diagnosis below. **Exit 5** says neither this commit nor the default branch's head carries a single check-run, so this repository runs none and nothing is coming: go to Step 2, where clean's condition 1 reads it. **Anything else** never yielded a settled listing, which is not the same thing as a check that failed, and is the **third terminal state**: stop, and hand it back to a person with the exit status and what the script wrote. Don't read a listing off those and don't delegate a diagnosis: the cap prints the last listing it managed to read, so a failure conclusion sitting in a set still in motion would send a subagent to root-cause a check the run never waited out.

On that failing conclusion, delegate the diagnosis to a subagent: hand it the failing check, have it apply `superpowers:systematic-debugging`, and return only the root cause and a concrete fix plan, never the raw logs. Before applying it, confirm it's actually a fix — a diagnosis showing that the agreed design itself is wrong is not one; take **Escalation** instead. Otherwise apply it as an ordinary change: implement, verify, simplify with `simplify-code`, review with `review-code` — never re-running `implement-work`'s own completion gate — then commit and push, never straight to the default branch. Go back to this step's CI watch. Where that `review-code` stops with a blocking finding open — a `needs-user`, or a stop under `using-dude`'s **Loop convergence** — the fix goes no further either: that is the **third terminal state**, but for the Critical finding that invalidates the agreed design, which takes **Escalation** exactly as a diagnosis showing the same does. All three exits commit nothing and push nothing, so the tree is left uncommitted: it carries the diagnosis fix and whatever accepted fixes `review-code` applied and verified before it stopped, and what differs between the exits is only that last round's own accepted fixes, held unapplied on a `needs-user`. Name what the uncommitted tree holds, keeping the diagnosis fix and the applied fixes apart, and hand over with it — on a `needs-user`, the open findings, the question the worker put to a person, and that round's unapplied verdicts; on a **Loop convergence** stop, the open findings and where the disagreement stands, as that rule requires; and on the Critical, the diagnosis and the tree's contents, inside the account of where the review had got to that **Escalation** below already asks for.

**Clean = exit 0 with every conclusion passing, or exit 5.** A failing conclusion is the one non-clean answer that loops, subject to `using-dude`'s **Loop convergence**. A round here is one watch → diagnose → fix → push cycle; a failure is the same one when the same check fails for the same reason a previous round's fix targeted.

## Step 2: Request review, then loop on feedback

Request review from both Claude and Copilot when both are available — they catch different things. Skip whichever isn't; if neither is, still run 2-0, then skip straight to Step 3 — that path pushes nothing, so the HEAD Step 1 already watched green is still the tip.

### 2-0. Verify PR body issue links

Before reviewers are asked to read it: for every issue reference in the body, resolve it against the repository the reference itself names — the one in a reference qualified as `owner/repo#NNN`, and the PR's own only for a bare `#NNN` — and confirm it's the intended issue. A reference carrying a closing keyword takes one confirmation more — that it resolves to an **issue** at all. A successful lookup is not that confirmation: issues and PRs share one number space, and a PR's title can echo the issue it closes, so the title alone settles nothing. The record's web URL is what separates them — `/issues/` against `/pull/` — and a closing keyword on a PR number closes nothing, leaving the issue open after the merge. Ask the user when the intended repository is ambiguous rather than guessing. Correct any wrong link before continuing.

### 2-1. Request the reviewers

- **Claude**: `<skill-dir>/scripts/watch-claude-review.sh <branch>` — exit 0 means available (its recent runs come back as JSON), exit 3 means no `@claude` workflow, so skip Claude; anything else, stop and inspect. That exit status is the whole availability test — don't go searching the workflows yourself. When available, post a request comment in standard Japanese with a short "特に見てほしいポイント" list; on a re-request after a new push, include the current HEAD SHA so the review targets the latest state.
- **Copilot**: record the baseline first — `<skill-dir>/scripts/list-copilot-reviews.sh <owner> <repo> <pr-number>`, saving its output unmodified as the `<baseline-file>` that 2-2 passes to `watch-copilot-review.sh`, **before** requesting anything (`gh-mechanics.md`'s "## Recording the Copilot baseline" — taken afterwards, the baseline could already include the review being waited for). Then `<skill-dir>/scripts/request-copilot-review.sh <owner> <repo> <pr-number>` — exit 0 means requested, exit 3 means unavailable here (skip Copilot), exit 4 means the request couldn't be read back (stop), anything else also stops.

### 2-2. Wait for the review (bound the wait)

- **Claude**: only if 2-1 found the workflow and posted a request. Tie completion to the run itself, never to comment counts: list runs again with `<skill-dir>/scripts/watch-claude-review.sh <branch>`, match the run by `displayTitle`, a `createdAt` after the request comment was posted, and a conclusion that isn't `skipped` — branch, `headSha`, and time alone each match the wrong run or none, per that script's own header — then block on it with `<skill-dir>/scripts/watch-claude-review.sh <branch> <run-id>` — exit 0 means it succeeded, non-zero means it didn't, or the call itself failed.
- **Copilot**: wait for a review carrying an `id` the 2-1 baseline didn't have — `<skill-dir>/scripts/watch-copilot-review.sh <owner> <repo> <pr-number> <baseline-file>`, which polls `list-copilot-reviews.sh` and answers with the reviews that baseline didn't hold. Compare against that baseline, never against your own handling history. Identify the reviewer by author login (`gh-mechanics.md`'s "## Identifying a bot"), never by timestamp. Don't wait for a formal approval — Copilot commonly only ever returns a comment-only verdict.
- **Always bound the poll**, with an iteration cap and an explicit bail-out. On timeout, stop and tell the user rather than looping forever.

### 2-3. Evaluate and address feedback

Delegate collection to a subagent: gather every reviewer comment left after the latest push, together with whatever `<skill-dir>/scripts/list-suppressed-comments.sh --full <owner> <repo> <pr-number>` printed, dedupe, and return a structured list of findings, each with `file:line`, the thread or comment id where it has one — a suppressed finding has none — and a one-line summary. Then fan out one subagent per finding, launched together in a single message, each applying `superpowers:receiving-code-review` to its one finding and returning `accept` (with the fix), `reject` (with the technical reason), or `needs-user`.

**Count the `needs-user` verdicts back in the orchestrator before anything else.** One or more ends the round before anything is applied: it takes the **third terminal state**. Nothing is fixed, nothing is committed or pushed, no thread is replied to or resolved, and no verdict comment is posted. Hand over every `needs-user` finding with its location and why the worker put the decision to a person, and the round's other verdicts with it — each `accept` with its fix, each `reject` with its reason — so none of it has to be worked out again. Applying those first is the obvious alternative, and it is the wrong one: the person's answer can move what the other fixes rest on, while holding them costs nothing, since a worker's return is advisory text and an unapplied fix is still in hand.

Otherwise, sequentially — these mutate shared state: fix every `accept`, on the discipline the next paragraph sets; commit and push; reply to every thread, `reject` included, explaining the pushback; resolve the round's threads together in one call to `<skill-dir>/scripts/resolve-thread.sh <owner> <repo> <pr-number> <comment-id> [comment-id...]`; record the round's verdict on every finding that has no thread — accepted and rejected alike, with the same reasoning — in one PR comment, since with no thread it reaches neither of those two calls; write each thread reply in the language and tone of the comment it replies to; neither a thread reply nor the aggregate PR comment may mention `@claude`, which would re-trigger the workflow.

A round's fixes take Step 1's ordinary-change discipline with two departures. **`review-code` is dropped outright** — whatever this round pushes goes back to 2-1 for the reviewers to read, while a Step 1 fix reaches Step 3 unread wherever neither reviewer is available. **`simplify-code` is skipped on a declared test**, the same shape as the small-change lane in `using-dude`'s **Workflow selection**: skip it where every fix in the round changed only what its own finding named — no new branch, no new helper, no logic reimplemented that already exists elsewhere — and declare the skip in one line in the round's report to the caller, per `using-dude`'s **Stage boundaries**; anything else takes the pass. The two depart on different terms because the reviewers substitute for them unequally: a strong substitute for `review-code`, and an expensive one for `simplify-code` — a "this duplicates what's already there" that one local pass catches on the spot costs a whole external round to come back through a reviewer.

**A finding is addressed when its fix has been pushed, or when this round's rejection has been posted where the finding lives** — a thread reply where the finding has a thread, that round's verdict comment where it has none, as a suppressed finding does. So the round's tail branches on whether it pushed anything: it did → back to 2-1, re-requesting both reviewers against the new tip; it applied nothing → every finding of the round is addressed, so carry on to the clean judgment on the same commit. Re-asking reviewers about a commit nobody has touched returns what already came back, and for a suppressed finding that is the same block again, which no reply and no resolution can remove.

### Clean judgment & stop conditions

**Clean** holds when all five of these are true **on the same commit** — the tip of `<branch>` at the moment you judge:

1. the checks came back clean in Step 1's sense — exit 0 with every conclusion passing, or the exit 5 that says this repository runs none;
2. Claude leaves no actionable feedback unaddressed — every comment is either "looks good"/LGTM-equivalent, or a finding of this round, addressed in 2-3's sense (a human reviewer's comments count the same way);
3. Copilot's latest round leaves no actionable finding unaddressed: `<skill-dir>/scripts/list-unresolved-threads.sh <owner> <repo> <pr-number>` **exits 0 with empty stdout**, and `<skill-dir>/scripts/list-suppressed-comments.sh <owner> <repo> <pr-number>` **exits 0** with every `path:line` it prints a finding of this round, addressed in 2-3's sense — its **exit 4** says Copilot's block stopped parsing, which is the **third terminal state**, never another round. The two sides are read differently because Copilot's findings arrive on two paths and neither script sees the other's: a comment listing carries no resolution state, and a finding Copilot suppressed never became a thread at all, so it stays in that listing regardless of how it is addressed — **addressed, not absent, is all the suppressed side can be read for** — while a rejected thread is replied to and resolved, and so does drop out of the thread listing. **The review body's own `Comments generated: 0 new` is not evidence here** — that count leaves suppressed findings out, so a review reporting zero new comments can still carry one;
4. the PR's base is the one Step 1 most recently resolved;
5. mergeability came back **`MERGEABLE`** — the field `gh-mechanics.md`'s "## Mergeability" says to trust, never its sibling, which varies with the caller's own push permission rather than with anything about the branch. `UNKNOWN` is not a pass: it means the remote couldn't settle it even after the bounded re-read, so nothing is known yet.

**Clean is a property of one commit, not a total accumulated over rounds.** A push invalidates all five at once — nobody has read the new diff, and nothing has run against it — so a result from before a push is not evidence about what the branch carries now.

When it isn't clean, what to do follows from which condition failed, and every remedy short of a terminal state re-enters the loop — from 2-1 where it pushed, and from this judgment where it applied nothing:
- conditions 2 or 3 (reviewer feedback) → address it, per 2-3 — except `list-suppressed-comments.sh`'s **exit 4**, which is not feedback to address but the **third terminal state**: Copilot's format moved, and no round of fixes can move it back;
- condition 1 → per Step 1's own branch on the exit status: a failing conclusion is diagnosed and fixed there, borrowing the diagnosis and not Step 1's own loop, so it isn't counted against Step 1's rounds; a status that yielded no settled listing is the third terminal state here too;
- condition 4 (base drift) → pull the resolved base in with `retarget-pr.sh`, per Step 1 — it pushes the merge itself, so the next round starts from 2-1 on the new tip;
- condition 5 (mergeability) → the **third terminal state**, per Step 1's handling of `CONFLICTING`/`UNKNOWN`.

**Stop the loop when any of these holds — read in order, and take the first that applies; otherwise keep looping:**

1. Clean, per above → Step 3.
2. **A finding invalidates the agreed design** → stop and take **Escalation**. Check this on every round, before the rest — don't fix it here, and don't carry it into another round.
3. **Any finding came back `needs-user`** → the third terminal state, per 2-3.
4. **Mergeability is anything but `MERGEABLE`** → the third terminal state, per above. `UNKNOWN` belongs here as much as `CONFLICTING` does.
5. **LGTM-equivalent twice in a row, with the other four conditions true on the HEAD it leaves from** → Step 3. This is the stricter exit `using-dude`'s **Loop convergence** allows on top of clean, and being stricter it carries every one of clean's other conditions too — a red check, base drift, or a conflict all mean this doesn't hold either.
6. **A non-clean stopping condition in `using-dude`'s Loop convergence fires** → stop and hand the user the decision.

A round here is one 2-1 → 2-2 → 2-3 → clean-judgment cycle; a check confirmed and the fix it forces sit inside that same round rather than starting a new one. Two findings are the same one when a later round makes the same claim about the same place, whichever reviewer raises it — and, for a round that went non-clean on a check, when both the check and the cause behind it are what a previous round's fix already targeted.

## Step 3: Finish

Once Step 2 exits clean, re-confirm the same five conditions on the HEAD it leaves from — measuring only, fixing nothing. Anything that needs fixing here takes the third terminal state instead: report what was found and where the PR and branch stand, and stop — fixing at this point would flip the PR to a state nobody has actually reviewed.

Otherwise branch on the flag Step 0 recorded:
- **ready-on-clean = yes**: mark the PR ready. Claude's LGTM is a comment, not a formal approval, so a branch-protection rule requiring an approving review may still block merge — flag that to the user, since a human approver may be needed.
- **ready-on-clean = no**: report that CI and review are clean.

**This flow has three terminal states: ready, draft, and handed back to a person.** The third is reached from Step 1's base-settlement, from a `review-code` that stopped with a blocking finding open on a Step 1 fix — whose uncommitted tree that step's own clause names — from a `needs-user` finding in 2-3, from `list-suppressed-comments.sh`'s exit 4 in the clean judgment, from the mergeability stop condition above, or from this step's own re-confirmation — every one of them just reports what was found and stops. **None of them is Escalation, and none of them calls `plan-work`**: a conflict, a drifted base, or a finding only a person can settle has not touched the agreed design, so the question re-approval asks — which part of the design this undoes — has no honest answer there.

Either way, the run ends here. Everything depending on the merge belongs to a person — report it as hand-over and act on none of it:
- **the parent issue**, whenever one backs this sub-issue: GitHub doesn't close a parent when its children close, so report the sub-issue's state as of now, and if it's the last one open, that the parent becomes closable on this merge — then leave it;
- **the workspace and the branch**, both outliving this run — name the path 0-3 reused or attached, and the branch;
- **the next sub-issue**, when children remain open — say which.

Carrying on into the next one would do `implement-work`'s job with none of its gates. The one exception is an explicit instruction already in the chat covering what comes after — and even then this run still ends here: what that licenses is starting the next run through its own entry and gates, not extending this one.

## Escalation

The single source is `using-dude`'s **Escalation**; this phase is not an exception to it. Hand `plan-work`'s entry the three things it asks for: the finding — what it showed, and which part of the agreed design it undoes; the branch name; and the branch's state — whether it's pushed, and the `<PR>` this run was driving. Add where the review had got to: the round the finding surfaced on, and what was already fixed and pushed. Leave the PR as it is — don't close it, and don't change its draft state.
