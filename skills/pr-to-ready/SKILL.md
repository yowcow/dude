---
name: pr-to-ready
description: Use to take an open PR to ready, or a branch with no PR yet to ready.
---

# pr-to-ready

Take an open PR to a reviewed one: resolve the run from the PR's number or URL, set up the workspace its head branch needs, then loop until CI passes and the review is clean.

- The only PR-status change this flow makes is draft → ready, and it makes that one only when the user asked for it up front and the run came out clean; anywhere else, clean or not, the PR's status is left as it was found.
- Precondition: a PR whose commits are already verified — normally the draft PR `implement-work` left behind.
- A branch carrying no PR yet is the fallback entry, and an unpushed one is not a blocker: push it, open the draft PR, and go on.
- This flow ends at one of three terminal states: ready, draft, or **handed back to a person** when something surfaces that this run cannot resolve on its own.

## Orchestration model

Run this skill as an orchestrator: the main loop owns control flow, every decision, and every state-mutating action. **Steps that change state** run sequentially, never in parallel; what may go out together in one message is exactly this — the clean judgment's reads of the six conditions, Step 2-1's Claude availability check and Copilot baseline for whichever of Copilot and Claude Step 0 selected, plus 2-1's `vet-code` call where requesting-code-review is selected, which goes out as soon as 2-1's selected requests have been sent and runs on through 2-2's waits, Step 3's re-confirmation script together with condition 6's read (condition 2's read waits until that script returns), and the round's `judge-findings` call on the external findings, its workers going out together — one per group that call split them into, none taking a verdict from another of this round's judges as input — starting the moment those findings are in without waiting for `vet-code`. No judge call shares a message with another round's: the next round's review waits on this round's verdicts and the fixes they force.

**Never delegate:** the clean judgment and stop conditions, including reading whether checks pass; any change that touches the worktree, together with committing and pushing it; and any write to the PR itself — comments, thread replies, thread resolution, marking it ready.

**Delegate:** diagnosing *why* a check failed, wherever that comes up — deciding whether checks are green stays above, only the diagnosis of a red one is handed off; and collecting reviewer comments into a structured list of findings. The requesting-code-review review and the judging of findings are `vet-code`'s and `judge-findings`'s. Every delegated subagent is read-only and advisory: it investigates and proposes, and the orchestrator is the one that applies a change, commits, and pushes.

Every delegation and skill invocation it makes carries the measurement record's path or, where no record covers the tree the worker will judge, says that there is none and what is missing, per `using-dude`'s **Measurement records**.

This skill dispatches no marked worker of its own: the reviewer and the judging workers are `vet-code`'s and `judge-findings`'s, and it re-judges none of their verdicts. Invoke `propose-alternatives` and, on a finding, `review-findings` by name; those skills own their procedures.

## Step 0: Set up the run

### 0-1. Ask ready-on-clean and reviewers

Ask the user two things, once:

- Once CI is green and review is clean, should this run mark the PR ready, or leave its status as it is? Record the answer as the **ready-on-clean** flag. Step 3 branches on it.
- Which of Copilot, Claude, and requesting-code-review should this run request? Ask it as a pick-any choice prompt over the three, plus none. Offer all three verbatim, without omission or rename — a dropped or respelled choice silently proceeds without the wanted review. Record the answer as the **reviewers** set. Step 2-1 requests only from that set. Do not probe availability here — that is 2-1, after 2-0.

### 0-2. Resolve the run from the PR reference

Bind the run from the caller's reference — a PR number or a PR URL. If none was given, ask; **don't guess it from the current checkout**, whose repository need not be the PR's at all.

Call `<skill-dir>/scripts/resolve-pr-entry.sh <pr-ref>` once. It resolves the reference against the repository the reference itself names, checks that this working tree is a checkout of that repository, and answers on one line. Branch on it:

- `PR <n> branch=<head> base=<base> repo=<owner>/<repo> draft=<bool>` — bind `<PR>`, `<branch>`, and the `<owner>` and `<repo>` every later script call takes; none of those three is re-derived from the checkout again. `<base>` is the base the PR points at **now**, which is not the same question as the base it *should* sit on: Step 1 re-resolves that and may replace it.
- `STOP <slug>` — report the stop and end the run. Nothing downstream has a repository, a branch, or a base it could work from.

**Fallback — a branch with no PR on it yet.** Where the caller gave a branch name instead (work `implement-work` left before its hand-off, a branch cut outside dude, or a PR deliberately skipped), call `tools/ensure-draft-pr.sh <branch>` first, and drive it to a PR exactly as `implement-work`'s **Hand off** does — `NEED`, the create answer and its read-back, `STOP ask-base-repo` and `STOP fork-unread`; title and body follow that section too.

- It pushes the branch if only a local ref exists, looks for a PR already on it, and only when none is found answers with where to open one.
- On a `PR` line, found or created, feed `<n>` back through `resolve-pr-entry.sh` above so the rest of the run binds from one place; on any other `STOP`, report it and end the run.

### 0-3. Prepare the workspace

`<branch>` need not be checked out here, or exist here at all — a fresh session entered from a PR URL is the ordinary case — and every later step writes to a working tree: Step 1's `retarget-pr.sh` merges the base and pushes it, and Step 1's diagnosis fixes and 2-3's blocking `accept` fixes commit and push. Preparing it once here rather than where each of those needs it keeps one step instead of three.

Call `tools/attach-workspace.sh <branch> <path>`. `<path>` follows `superpowers:using-git-worktrees`'s own directory convention. Branch on the one line it prints:

- `REUSE <path>` — a worktree already carries `<branch>`, and it need not be clean: this flow's third terminal state deliberately leaves a tree uncommitted, and the same tree outlives the run that left it.
  - Measure it before binding it — run `tools/check-clean.sh` **from `<path>`**, which takes no argument and reads the tree it runs in, so running it where the session started measures a tree this run will never touch.
  - Clean: use it as-is.
  - Anything pending — **stop.** It is work this run did not write, and Step 1's diagnosis fix and 2-3's blocking `accept` fixes would carry it into the PR unread by anyone; report what the script printed and hand the tree back to a person to say whose it is.
- `ATTACHED <path>` — the branch existed locally or on the remote, and a new workspace now tracks it. Use it.
- `CREATE` — **stop.** A PR's head branch exists on its repository's remote by definition, and 0-2 has already established that this checkout is that repository, so nothing to attach to means the branch was deleted under an open PR. Report it; don't cut a fresh branch, which would put an empty history under the name the PR points at.

Once `REUSE` has measured clean or `ATTACHED` has answered, run `<skill-dir>/scripts/clear-recheck-record.sh` and `<skill-dir>/scripts/exit-batch-record.sh clear` from `<path>`, before anything else there, so a new run starts with no batch marked. The record Step 3's re-confirmation leaves outlives the run, so an earlier run on the same SHA — one with ready-on-clean = no, say — would otherwise leave Step 3's ready open to a run that never re-confirmed.

**Run every later step from that workspace.** Without this, the run edits, commits and pushes in whatever tree the session started in — with `<branch>` unchecked-out, that is whatever branch was: Step 1's diagnosis fix and 2-3's blocking `accept` fixes are committed onto the default branch and pushed there, reviewed by nobody, while the PR they were written for does not move.

## Step 1: Settle the base, then get CI clean

Before watching CI, settle whether the base is still the right one — the prerequisite's state can have moved since Step 0.

1. Re-resolve it: `tools/resolve-pr-base.sh <branch>` → `BASE <name>`, `NEED <token>...` or `STOP <slug>`. On `NEED`, read the facts it names as `implement-work`'s `references/facts.md` defines them, add them to one facts file, and run it again with `--facts <file>` added, for as long as it asks. This is the base the branch *should* sit on, read from its `Base-Branch:` trailer and the prerequisite's current state — a different question from the `<base>` 0-2 bound, which is the one the PR points at now.
2. Check the PR against that answer: `<skill-dir>/scripts/check-pr-state.sh <owner> <repo> <pr-number> <base>` → `BASE-OK|BASE-DRIFT <current-base> MERGEABLE|CONFLICTING|UNKNOWN`, or `STOP <slug>`. The name it prints is the base the PR points at **now**, not the one you passed in — which is what makes `BASE-DRIFT` worth reading. Read-only: it measures and never fixes.
3. On `BASE-DRIFT`: pull the resolved base in with `<skill-dir>/scripts/retarget-pr.sh <owner> <repo> <pr-number> <branch> <base>` → `BASE-OK <base>` (nothing to do), `RETARGETED <old> <new>` — the merge is pushed, so CI below runs against the new tip rather than the one it already passed on — or `STOP <slug>` on a conflict while merging the new base in.
4. On `CONFLICTING`, or on an `UNKNOWN` that stands after the script's own bounded re-read: neither is something to fix here — both are the **third terminal state**.
   - Stop, and hand the branch back to a person with what was found; don't attempt a resolution, and don't take an undetermined mergeability for a clean one.
   - **Name `implement-work` as where it goes back to** — a person's explicit re-entry, never a return this flow makes on its own. Its completion gate absorbs the base and re-verifies: with no destination named, the person's only cue is the PR they were already in, so they re-enter `pr-to-ready` and land on this same terminal state again, having changed nothing.

Then watch CI with `<skill-dir>/scripts/watch-checks.sh <owner> <repo> <sha>`, and branch on its **exit status** before reading anything it printed.

- **Exit 0** prints one line per check, name, status, conclusion, and is the only status whose conclusions are a verdict on anything. Whether they pass is read here, never by the script. Every one passing goes to Step 2 and a failing one goes to the diagnosis below.
- **Exit 5** says neither this commit nor the default branch's head carries a single check-run, so this repository runs none and nothing is coming. Go to Step 2, where clean's condition 1 reads it.
- **Anything else** never yielded a settled listing, which is not the same thing as a check that failed, and is the **third terminal state**. Stop, and hand it back to a person with the exit status and what the script wrote. Don't read a listing off those and don't delegate a diagnosis. The cap prints the last listing it managed to read, so a failure conclusion sitting in a set still in motion would send a subagent to root-cause a check the run never waited out.

On that failing conclusion, delegate the diagnosis to a subagent: hand it the failing check and, where a measurement record this run holds carries the identity of the tree that check failed on, its path; where none does, say so and what is missing in the dispatch. Name the directory it may write large output under, per `using-dude`'s **Measurement records**. Have it apply `superpowers:systematic-debugging`, and return the root cause and a concrete fix plan as before — the failed check's own logs never standing in for them — together with the command it ran and that command's raw output, which the orchestrator records as a measurement record.

- Confirm it is actually a fix before applying it. A diagnosis showing that the agreed design itself is wrong is not one; take **Escalation** instead.
- Otherwise apply it as an ordinary change: implement, verify, simplify with `simplify-code`, review with `review-code` — handing that call the starting round number S=1, and the judge record directory path, this worktree's own `dude-measurements/implement-work` record dir (the same dir the judge-records check reads) — and handing each the measurement record's path or, where no record covers the tree the worker will judge, that there is none and what is missing — never re-running `implement-work`'s own completion gate — then commit, back-patch each pair input file's envelope Commit: and Tree: lines to the committed tree with its body otherwise unchanged (verdict files' Commit:/Tree: echo is unread and left as written), and push, never straight to the default branch. Before that push, run the `implement-work` judge-records check (`check-judge-records.sh` in that skill's `scripts/` dir) from `<path>`; on any line other than `OK` take the third terminal state with the script's line in the hand-over — that exit is committed-but-unpushed, so hand over that commit's SHA with the script's line: the next run must re-verify that commit rather than push it as-is — applying no fix on top of an unverified tree. That script's header is the single source for what each line means. Go back to this step's CI watch.
- Where that `review-code` stops with a blocking finding open — a `needs-user`, or a stop under `using-dude`'s **Loop convergence** — the fix goes no further either: that is the **third terminal state**, but for the Critical finding that invalidates the agreed design, which takes **Escalation** exactly as a diagnosis showing the same does.
- The three review-code-stop exits commit nothing and push nothing, so the tree is left uncommitted. (The gate-failure exit in the preceding bullet is committed-but-unpushed.) It carries the diagnosis fix and whatever accepted fixes `review-code` applied and verified before it stopped. What differs between the exits is only that last round's own accepted fixes, held unapplied on a `needs-user`.
- Name what the uncommitted tree holds, keeping the diagnosis fix and the applied fixes apart, and hand over with it. On a `needs-user`, hand over the open findings, the question the worker put to a person, and that round's unapplied verdicts. On a **Loop convergence** stop, hand over the open findings and where the disagreement stands, as that rule requires. On the Critical, hand over the diagnosis and the tree's contents, inside the account of where the review had got to that **Escalation** below already asks for.

**Clean** per `using-dude`'s **Loop convergence** loop-clean = exit 0 with every conclusion passing, or exit 5. A failing conclusion is the one non-clean answer that loops, subject to `using-dude`'s **Loop convergence**. A round here is one watch → diagnose → fix → push cycle; a failure is the same one when the same check fails for the same reason a previous round's fix targeted.

## Step 2: Request review, then loop on feedback

Request review from each name in the reviewers set that is available. Skip a selected name that isn't; skip a name that isn't in the set, and do not probe it. If the set is empty, or every selected name is skipped, still run 2-0, then skip straight to Step 3 — that path pushes nothing, so the HEAD Step 1 already watched green is still the tip.

### 2-0. Verify PR body issue links

Before reviewers are asked to read it: for every issue reference in the body, resolve it against the repository the reference itself names — the one in a reference qualified as `owner/repo#NNN`, and the PR's own only for a bare `#NNN` — and confirm it's the intended issue.

- A reference carrying a closing keyword takes one confirmation more — that it resolves to an **issue** at all.
- A successful lookup is not that confirmation: issues and PRs share one number space, and a PR's title can echo the issue it closes, so the title alone settles nothing.
- The record's web URL is what separates them — `/issues/` against `/pull/` — and a closing keyword on a PR number closes nothing, leaving the issue open after the merge.
- Ask the user when the intended repository is ambiguous rather than guessing.
- Correct any wrong link before continuing.

Then invoke `propose-alternatives` once when the purpose is named. "Run 2-0" includes this invoke, including the empty-reviewers jump that skips 2-1.

- **Purpose:** what the issue behind a closing keyword states. Not the PR body, not a prescribed means, not a parent design in place of that issue. If that issue states no purpose → skip; do not invoke; chat the skip; continue. No new prompt.
- **Read-root:** the PR's base (the base the PR points at now, which Step 1 settled), fetched to its current tip before the worker reads it — not head, not the 0-3 workspace, not the session checkout.
- Else invoke `propose-alternatives` once with that purpose, read-root, and the measurement record's path or, where no record covers the tree the worker will judge, that there is none and what is missing.
- Compare with the current artifact per `propose-alternatives`'s **Caller contract** (purpose, means, cost).
- Empty finding → no `review-findings`; do not wait; continue; chat.
- Finding → `review-findings` one pass per `using-dude`'s **Stage boundaries**, carrying the measurement record's path, or saying that none covers the tree the worker will judge and what is missing; chat; wait for **continue** vs **revisit design** (revisit: the person returns to `plan-work` with the finding, the branch name, and that branch's state — what `plan-work`'s **Entry** asks for). Do not proceed past 2-0 — to 2-1, `vet-code`, or Step 3 — except on **continue**. **Don't follow `review-findings` onward to the next skill.** The proposal is not a finding, not `needs-user`, not Critical auto-reapproval, and is not posted to a PR (body or inline).

### 2-1. Request the reviewers

If the reviewers set is empty, skip this step and 2-2; go to Step 3.

Request only the names in the reviewers set. A name not in the set is a skip with no script exit — record that skip for the Request identity row, and do not call that reviewer's scripts or `vet-code`.

Capture the round-request SHA once before any selected request goes out.

Right after it, settle the round's inputs, whether or not requesting-code-review is in the set.

- **Scope**: the PR's range, ending at the round-request SHA, taken from `tools/resolve-range.sh <pr>`.
  - On `NEED`, read the facts it names as `implement-work`'s `references/facts.md` defines them into one facts file and run it again with `--facts <file>` added, for as long as it asks.
  - It answers `RANGE <base>..<head>`, `EMPTY`, or `STOP <slug>`, and only `RANGE` settles the scope. On `EMPTY` or `STOP`, take the **third terminal state**, reporting what it printed; a range built any other way, or a reviewer dispatched over an empty one, reads as a clean review.
  - A returned head that differs from the round-request SHA means the range does not cover what this round requests: take the **third terminal state**, reporting both SHAs.
- **Requirements**: the PR body, plus the issue 2-0 confirmed behind a closing keyword. Where there is neither, say so, and carry that as a caveat in the round's report to the caller.
- **Verdict record**: the verdicts this run's `vet-code` and `judge-findings` calls returned — each finding's `accept` or `reject` with its reason, an `accept` also saying whether the fix was pushed, with the pushed sha, or the finding was recorded only, and, for a non-blocking one, its value and reason, or that no value came back — beside the external side's value and reason for a merged one; for `apply` also its fix text, its state — pending, fixed with the pushed sha, dropped with the reason, or left unfixed with the reason — and its recorded SHA, the branch tip when its verdict was recorded, and each Declined to judge line rejected, with its reason. Earlier runs' verdicts are not rebuilt. It goes to the next round's `vet-code` and `judge-findings` calls as the earlier rounds. Each entry names the finding's `location` — for a suppressed finding the `path:line` string exactly as condition 3's projected listing prints it, never one cut out of the collection block's markup — and, where the reviewer gave one, its `severity`. A Copilot suppressed finding's entry also names the review id that listing prints on its first line, as `review`; a finding merged with one keeps that side's `review` and `location`, and the `review` and `location` pair is the key condition 3 and Step 3 judge it by. A replacement (2-3) updates the held entry in place and takes a new `review` and `location` pair only when the replacing finding carries one itself, as a suppressed finding or one merged with a suppressed side does; otherwise the held pair is kept.

Then request each name in the set:

- **Claude**: only if Claude is in the set. Resolve the default branch once here with `tools/resolve-default-branch.sh <owner>/<repo>` — exit 1 there is stop-and-inspect — and pass it as `<default-branch>` to every Claude listing this step and 2-2 make. `<skill-dir>/scripts/watch-claude-review.sh <owner> <repo> <branch> <default-branch>` — exit 0 means available (its recent runs come back as JSON), exit 3 means no `@claude` workflow, so skip Claude; anything else, stop and inspect.
  - The listing's exit status is the whole availability test — don't go searching the workflows yourself.
  - When available, post a request comment with a short list of what to focus on; every request comment includes that round-request SHA.
  - That trigger comment is the reference for a Claude-requested round. Record its id/URL at post time for the Request identity row.
- **Copilot**: only if Copilot is in the set. Record the baseline first, then request.
  - Baseline: `<skill-dir>/scripts/list-copilot-reviews.sh <owner> <repo> <pr-number>`, saving its output unmodified as the `<baseline-file>` that 2-2 passes to `watch-copilot-review.sh`, **before** requesting anything (`gh-mechanics.md`'s "## Recording the Copilot baseline").
  - Re-request: a re-request on the same SHA still records a fresh baseline and still requests, except once a measured full Clean held on that SHA — there, do not re-request on it. The blocking-reject row-6 loop and other re-entries that never measured full Clean still go back to 2-1.
  - Request: `<skill-dir>/scripts/request-copilot-review.sh <owner> <repo> <pr-number>` — exit 0 means requested, exit 3 means unavailable here (skip Copilot), exit 4 means the request couldn't be read back (stop), anything else also stops. On exit 0 only, record that same round-request SHA for the Request identity row.
<- **requesting-code-review**: only if requesting-code-review is in the set. Call `vet-code` once for the round, handing it the round's scope (the range settled above, as a committed range), the PR body as what was implemented, the requirements, the verdict record, the measurement record's path or, where no record covers the tree the worker will judge, that there is none and what is missing, and the judge record directory path and the round number — numbering starts at 1, incrementing per round — from S+k where Step-1's review-code pass consumed k rounds from S, per its Report row; call it right after the selected Claude/Copilot requests are sent, never after their wait.

If this step requested nobody, skip 2-2 and go to Step 3.

### 2-2. Wait for the review (bound the wait)

- **Claude**: only if 2-1 found the workflow and posted a request. Tie completion to the run itself, never to comment counts: list runs again with `<skill-dir>/scripts/watch-claude-review.sh <owner> <repo> <branch> <default-branch>` — the default branch 2-1 resolved — match the run by `displayTitle`, a `createdAt` after the request comment was posted, and a conclusion that isn't `skipped` — branch and time alone each match the wrong run or none, per that script's own header — then block on it with `<skill-dir>/scripts/watch-claude-review.sh <owner> <repo> <branch> <run-id>` — `<run-id>` is that matched entry's `databaseId`, which is also what tells the two modes apart — exit 0 means it succeeded, non-zero means it didn't — a run that concluded `skipped` included, which never reviewed anything — the call itself failed, or the run had still not completed when that call's own bound ran out.
- **Copilot**: only if 2-1 requested Copilot. Wait for a review carrying an `id` the 2-1 baseline didn't have — `<skill-dir>/scripts/watch-copilot-review.sh <owner> <repo> <pr-number> <baseline-file>`, which polls `list-copilot-reviews.sh` and answers with the reviews that baseline didn't hold. Compare against that baseline, never against your own handling history. Identify the reviewer by author login (`gh-mechanics.md`'s "## Identifying a bot"), never by timestamp. Don't wait for a formal approval — Copilot commonly only ever returns a comment-only verdict.
- **requesting-code-review**: only if 2-1 called `vet-code`. Await its return inside the bound below, then post the round's review comment per **Posting** below, recording its id/URL at post time for the Request identity row. Its wait and the externals' are independent: external findings go on to 2-3 as soon as the externals' waits complete, without waiting for `vet-code`.
- **Always bound the wait**, poll or subagent return alike, with an iteration cap and an explicit bail-out. On timeout, stop and tell the user rather than looping forever.

### 2-3. Evaluate and address feedback

Delegate collection to a subagent:

- Gather from the Copilot review 2-2 waited for, and from the Claude run 2-2 waited for — not every comment left after the latest push — together with whatever `<skill-dir>/scripts/list-suppressed-comments.sh --full <owner> <repo> <pr-number>` printed.
- Call that one only where 2-2 came back with a Copilot review the 2-1 baseline didn't hold, since the script reads whichever Copilot review is latest and knows nothing of rounds, so on a round where Copilot was skipped its block is an earlier round's, already dealt with and left to the clean judgment's leftover handling.
- Read the same listing without `--full` on that round too, as the source of those two values for the suppressed findings: its first line is the review id, its second is the `suppressed` count line, and the lines after those are the `path:line` entries. A location cut out of the `--full` block's markup is not that string, so it never matches what condition 3 compares.
- Dedupe, and return a structured list of findings, each with `file:line`, the thread or comment id where it has one — a suppressed finding has none — where the reviewer gave one, its `severity`, and a one-line summary. A suppressed finding also carries the review id printed on the projected listing's first line, and its `path:line` exactly as that listing prints it — the two values the verdict record takes as `review` and `location`.
- Do not re-collect a thread this run already resolved. A new review that repeats the same claim at the same place is a new finding; Loop convergence still identifies two findings as the same one by place and claim. A finding that makes the same claim about the same location as a pending item replaces it once it has passed this round's merges: its verdict, severity, value, fix, and recorded SHA stand, no second item is added, and there is no keep-both branch. If the replacing finding is blocking it is fixed as blocking; if its verdict is not an `apply` it is no longer pending and is posted under that verdict.
- Hand the collected external findings to `judge-findings` as items, with the round's scope, requirements, the earlier rounds' record, the measurement record's path or, where no record covers the tree the worker will judge, that there is none and what is missing, the judge record directory path and the round number with that same none-covers caveat, and, as the acceptance criteria, the "The spec is a vision document" paragraph of `superpowers:requesting-code-review`'s reviewer template, verbatim. Call it only when there is at least one external finding (LGTM and empty reviews skip it), and start it as soon as collection returns, without waiting for `vet-code`.

**A finding is blocking, or non-blocking.** Blocking means a severity of Critical or Important, and it means no severity at all; a severity that is neither of those nor Minor is blocking too, so no finding falls between the two buckets. Two kinds are non-blocking whatever their severity: a Minor, and a finding Copilot suppressed. A finding merged from a `vet-code` finding and an external finding is blocking when either side is. A blocking `accept` is always fixed; it takes no value vote, whatever value `judge-findings` returned. A non-blocking `accept` takes that value: `apply` makes it an **adopted item**, fixed as set out below, and `record` is recorded with the fix it would take and never fixed. A non-blocking `accept` that arrives with no value is `record`, and is carried as having no value come back; one merged from a `vet-code` and an external finding is `apply` when either side is, and is carried as having no value come back too when its `vet-code` side came back with no value and its external side is not `apply`. A non-blocking finding is never fixed or pushed by itself and never starts another round.

**An adopted item is held as text only** — its fix in the verdict record and the pending state in the PR's verdict comment, nothing in the tree: no uncommitted change, no unpushed commit. It stays pending until a push carries it or an exit settles it. Before any push carries it, a pending item is **stale**, and is dropped with its reason, when the path it targets changed between its recorded SHA and the branch tip, or when a blocking fix of a different claim touches that place. A blocking fix of the same claim is not a drop: it replaces the item, per the collection rule in 2-3.

**Nothing is fixed, committed, pushed, replied to, resolved, given a verdict comment, or walked on the stop list until every verdict of the round is in — `vet-code`'s and `judge-findings`'s alike — and the `needs-user` verdicts are counted over all of them first.** One or more ends the round before anything is applied: it takes the **third terminal state**.

- The round's review comment 2-2 posted from `vet-code`'s return stays on the PR: it is the reviewer's own output, as though an external reviewer had posted it.
- Nothing is fixed, nothing is committed or pushed, and nothing else is written to the PR; the values actually read go in the hand-over with the verdicts below.
- Hand over every `needs-user` finding with its location and why the worker put the decision to a person, and the round's other verdicts with it — each `accept` with its fix, each `reject` with its reason — so none of it has to be worked out again. Every hand-back — a third terminal state or **Escalation** — also lists each pending adopted item with its fix text and recorded SHA as unapplied, and says its planned line is still on the PR; nothing is posted at that stop.
- Applying those first is the obvious alternative, and it is the wrong one: the person's answer can move what the other fixes rest on, while holding them costs nothing, since a worker's return is advisory text and an unapplied fix is still in hand.

A `vet-code` finding and an external finding of the same round that make the same claim about the same place are one finding. Where their verdicts agree it is recorded once, and where it is blocking its fix is applied once. Where they disagree, the round takes the **third terminal state** with the same hand-over as a `needs-user`, both verdicts included: this skill re-judges neither.

Otherwise branch on this round's findings.

When there is no finding from any reviewer (LGTM or empty reviews): go to the clean judgment.

When there is at least one blocking `accept` (pure or mixed): walk row 2 of the stop list first, across every finding of the round — a fix pushed before that check is already published, and **Escalation** leaves the PR as it is. If it does not stop: before committing and pushing, run the `implement-work` judge-records check (`check-judge-records.sh` in that skill's `scripts/` dir) from `<path>`; on any line other than `OK` take the third terminal state with the script's line in the hand-over, applying no fix on top of an unverified tree. That script's header is the single source for what each line means. Then, if the check passed: sequentially — fix every blocking `accept`, and with them every pending adopted item that is not stale — the round's own and those held from earlier rounds — on the discipline the next paragraph sets; commit and push, which settles the pending items; then post per **Posting** below, each fixed item as fixed with the pushed sha and each dropped one as withdrawn with its reason. Every `record` accept is recorded by that post and fixed nowhere. Do not evaluate the six clean conditions. Walk only rows 4 and 6 of the stop list. If that walk does not stop, go back to 2-1.

A round's fixes take Step 1's ordinary-change discipline with two departures.

- **`review-code` is dropped outright** — whatever this round pushes goes back to 2-1 for the reviewers to read, while a Step 1 fix reaches Step 3 unread wherever neither reviewer is available.
- **`simplify-code` is skipped on a declared test**, the same shape as the small-change lane in `using-dude`'s **Workflow selection**.
  - Skip it where every fix in the round changed only what its own finding named — no new branch, no new helper, no logic reimplemented that already exists elsewhere — and declare the skip in one line in the round's report to the caller, per `using-dude`'s **Stage boundaries**; anything else takes the pass.
  - The two depart on different terms because the reviewers substitute for them unequally: a strong substitute for `review-code`, and an expensive one for `simplify-code` — a "this duplicates what's already there" that one local pass catches on the spot costs a whole external round to come back through a reviewer.

When every finding is an `accept` and none of them is blocking: do not fix, do not commit, do not push, and do not return to 2-1. Walk row 2 of the stop list first, across every finding of the round. If it does not stop, hold each `apply` item as planned, post per **Posting** below — each `record` accept with the fix it would take, each `apply` item as planned — and go to the clean judgment. Nothing was pushed, so the SHA is still this round's, and a clean answer takes Step 3 from it instead of forcing one more round over a fix nobody applied.

When the round has at least one blocking `reject` and no blocking accept:

- Do not fix, do not commit, do not push.
- Walk row 2 of the stop list first, across every finding of the round — a thread replied to and resolved before that check is published and no later round reads it again, and **Escalation** leaves the PR as it is.
- If it does not stop: post per **Posting** below. Do not evaluate the six clean conditions. Walk row 4 of the stop list even when the SHA did not change, judging mergeability alone.
- Then, only if that walk did not stop: read clean condition 3's two listings the way that condition reads them — its **exit 4** is the **third terminal state**, never another round, and a listing that did not exit 0 has no value for the next test.
- Only when both exited 0: if the SHA is still the one this round requested against, and the thread listing is empty while the suppressed listing carries an entry this run's verdict record does not cover — no recorded pair for it, or its pair names another review's id — take the **third terminal state** and do not go back to 2-1.
- If those do not all hold, walk row 6 of the stop list even when the SHA did not change, and if that walk does not stop, go back to 2-1.

When every `reject` the round has is non-blocking, and no accept is blocking: a blocking reject is the one case that re-reads its own pushback, because a wrong pushback there is what a later round would still catch. A non-blocking reject costs a whole round to re-read and cannot be fixed by one, so do not fix, do not commit, do not push, and do not return to 2-1. Walk row 2 of the stop list first, across every finding of the round. If it does not stop: post per **Posting** below, walk rows 4 and 6 of the stop list even when the SHA did not change, and go to the clean judgment. Nothing was pushed, so the SHA is still this round's, and a clean answer takes Step 3 from it.

**Posting**:

#### Where to write

- **The round's review comment** — the one 2-2 posts from `vet-code`'s return (posted once, there; 2-3 posts it no further). It carries each finding's severity, location, and the reviewer's own claim, plus every Declined to judge line as the reviewer stated it, the review range, and the round-request SHA; it carries no verdict. A Declined line that became a finding appears only under the Declined heading, with no severity or verdict there; its severity and verdict go in the verdict line or the thread reply. Post it even when there are no findings: write "No findings" in place of the finding blocks, keep any Declined to judge line, and still give the range and the round-request SHA. A round that did not call `vet-code` posts none.
- Where the round has at least one thread, reply to every thread, `reject` included, explaining the pushback — a `record` accept's reply also carries the fix it would take and says the code was left unfixed, with the reason, which for one carried as having no value come back is that the review did not say whether the fix is worth applying, beside the external side's reason for a merged one — and resolve the round's threads together in one call to `<skill-dir>/scripts/resolve-thread.sh <owner> <repo> <pr-number> <comment-id> [comment-id...]`. Write a reply in the states and verdict words of the verdict comment below, never the skill's own: right and fixed with the sha; right and left unfixed, with its reason; not right and code unchanged, with the reason the finding is wrong; or right and planned with the fix it would take, for a held adopted item. Its later fixed, withdrawn or left-unfixed state goes in the verdict comment, and only its verdict stays on the thread.
- Record the verdict on every finding that has no thread — the requesting-code-review findings not merged into an external thread, Copilot's suppressed ones, Claude's non-inline ones — and every adopted item's state change, in one new PR comment per posting moment. The skill sets no language for it: write it in whatever language suits the context or the user's environment. The verdicts are **right** and **not right**; the states are **fixed** with the pushed sha, **planned**, **left unfixed**, **withdrawn**, and **code unchanged** for a finding that is not right. Its first line is a legend saying in that language what each word it uses means: right means the finding is correct, not right means it is not; fixed means that commit fixed it, planned means it will be fixed in the next push, left unfixed means it is right but the code is left as it is, withdrawn means it was to be fixed and was cancelled. Then one line per finding, no fold, in this order: the state, the verdict with the finding's severity where one was given, its location, its claim, and its reason. A line starts with its state. A left-unfixed line for a `record` accept gives the reason the fix is not applied (what it changes only for readers and why that does not warrant a change), or, for one carried as having no value come back, that the review did not say whether the fix is worth applying, beside the external side's reason for a merged one; one for an adopted item gives the reason it was not applied, such as the batch limit. A not-right line gives, separately, why the finding is not correct; neither restates the verdict. A left-unfixed or planned line also carries the fix it would take. Record the comment's id/URL at post time. Threaded findings stay out of it, except that a threaded adopted item's later state change goes in it. The comment is posted when a state changes — after a push that carried items, and at an exit that settles pending items — even when the round had no finding; a round with nothing to report posts none. The earlier `not applied — accept (Minor)` shape is gone.

The review comment and the verdict line or thread reply that judges one of its findings are an **intended pair**, not a double post: the comment carries the reviewer's original text with the range it was read over and the round-request SHA, the verdict line or thread reply carries that finding's verdict in a threadless external finding's line shape — leading with the state only on the verdict comment's lines, a thread reply saying it in prose — so the verdict comment stands alone. Each finding's verdict lands exactly once — on its thread where it has one, otherwise in the verdict comment; a threaded adopted item's later state change, merged ones included, still goes in the verdict comment. Where the finding is the `vet-code` one merged into an external thread, that thread is its one place: reply to and resolve it, leave the merged finding out of the verdict comment except for an adopted item's later state change, and let the review comment keep the reviewer's text.

#### What the round's report carries

Every round's report to the caller carries these rows; the Request identity and Measured evidence rows are never written to the PR.

| Payload | Contents |
|---|---|
| Request identity | Request/skip decision per reviewer (with the exit behind it, or 'not selected — no probe' where the name wasn't in the set), the round-request SHA, on a Claude-requested round the trigger comment reference, and on a requesting-code-review round the `vet-code` return reference, the review comment id/URL and the verdict comment id/URL, each included where one was posted, plus any caveat on the round's inputs (no requirements, say). |
| Measured evidence | Measured-tip SHA where Clean was judged (omit it on rounds that never judged Clean), the listing exit codes and outputs actually read that round, and on a requesting-code-review round the review comment id and the verdict comment id, each included where one was posted. |
| Verdict | This round's verdict per finding (needs-user verdicts included), or LGTM where there was no finding. |

#### What not to write

| Route | Rule |
|---|---|
| Thread reply, verdict comment, review comment | May not mention `@claude`, which would re-trigger the workflow; any mention copied from a finding summary/body or verdict reasoning is written split (`@ claude`), so quoting a review can never re-trigger it. |

No line the skill writes into the verdict comment, a thread reply, or the review comment carries a SKILL-internal word — `accept`, `reject`, `not applied`, `recording-only`, `blocking`, `deferred`, `dropped`, a round number, a step name — so the timeline reads to someone who never saw this skill.

### Clean judgment & stop conditions

**Clean** per `using-dude`'s **Loop convergence** loop-clean holds when all six of these are true **on the same commit** — the tip of `<branch>` at the moment you judge, recorded as that judgment's measured-tip SHA:

1. the checks came back clean in Step 1's sense — exit 0 with every conclusion passing, or the exit 5 that says this repository runs none;
2. this round's Claude run leaves no blocking finding — every comment on it is "looks good"/LGTM-equivalent, or a Minor in this run's verdict record. Do not re-read comments from an earlier round this run already resolved. A Claude finding that carries no severity at all is blocking;
3. this round's Copilot review leaves no blocking or unrecorded finding:
   - `<skill-dir>/scripts/list-unresolved-threads.sh <owner> <repo> <pr-number>` **exits 0 with empty stdout**, and `<skill-dir>/scripts/list-suppressed-comments.sh <owner> <repo> <pr-number>` **exits 0 with every `path:line` entry it prints covered by a `review` and `location` pair in this run's verdict record** (empty stdout is covered trivially). Its **exit 4** says Copilot's block stopped parsing, which is the **third terminal state**, never another round.
   - The two sides are read differently because Copilot's findings arrive on two paths and neither script sees the other's: a comment listing carries no resolution state, and a finding Copilot suppressed never became a thread at all. So coverage by the recorded pair, not an "addressed" reject, is what the suppressed side requires — a rejected suppressed finding stays in the listing and its own pair covers it, while an entry with no pair, or with a pair naming another review's id, fails the condition. A rejected thread, by contrast, is replied to and resolved, and so drops out of the thread listing.
   - **The review body's own `Comments generated: 0 new` is not evidence here** — that count leaves suppressed findings out, so a review reporting zero new comments can still carry one;
4. the PR's base is the one Step 1 most recently resolved;
5. mergeability came back **`MERGEABLE`** — the field `gh-mechanics.md`'s "## Mergeability" says to trust. `UNKNOWN` is not a pass: it means the remote couldn't settle it even after the bounded re-read, so nothing is known yet.

6. this round's requesting-code-review block leaves no finding without a recorded verdict — every finding from this round's requesting-code-review identity (`vet-code`'s return + the review comment id + the verdict comment id where one was posted + round-request SHA) carries a recorded verdict: each blocking `accept` fixed and pushed, each non-blocking `accept` recorded per Posting — an adopted one as pending, fixed, dropped or left unfixed, never left without one of those — each `reject` recorded. Read it off the round's own verdict record, never a fresh listing; a round that did not request requesting-code-review passes this condition. On the no-finding or the non-blocking path this is definitional — the review comment never bars Clean by itself; rows 4/6 and row 5 enforce the leftover.

**Clean is a property of one commit, not a total accumulated over rounds.** A push invalidates all six at once — nobody has read the new diff, and nothing has run against it — so a result from before a push is not evidence about what the branch carries now. Record the measured-tip SHA with the values read for this judgment in the round's report to the caller (the Measured evidence row), so Clean on that SHA can be re-derived later.

When it isn't clean, what to do follows from which condition failed, and every remedy short of a terminal state re-enters the loop:
- conditions 2, 3, or 6 (reviewer feedback) → do not re-enter 2-3: walk the stop list with Clean false, and take the **third terminal state** when the leftover is not from this round's review — except `list-suppressed-comments.sh`'s **exit 4**, which is not feedback to address but the **third terminal state**: Copilot's format moved, and no round of fixes can move it back;
- condition 1 → per Step 1's own branch on the exit status: a failing conclusion is diagnosed and fixed there, borrowing the diagnosis and not Step 1's own loop, so it isn't counted against Step 1's rounds; a status that yielded no settled listing is the third terminal state here too;
- condition 4 (base drift) → pull the resolved base in with `retarget-pr.sh`, per Step 1 — it pushes the merge itself, so the next round starts from 2-1 on the new tip;
- condition 5 (mergeability) → the **third terminal state**, per Step 1's handling of `CONFLICTING`/`UNKNOWN`.

**Stop the loop when any of these holds — read in order, and take the first that applies; otherwise keep looping:**

1. Clean, per above — the first measured full Clean on that SHA — → the **Exit batch** below, then Step 3. Do not request again on a SHA once Clean held on it.
2. **A finding from any reviewer, requesting-code-review included, invalidates the agreed design** → stop and take **Escalation**. Check this on every round, before the rest — don't fix it here, and don't carry it into another round.
3. **Any finding came back `needs-user`** → the third terminal state, per 2-3.
4. **Mergeability is anything but `MERGEABLE`** → the third terminal state, per above. `UNKNOWN` belongs here as much as `CONFLICTING` does. Where this round's requesting-code-review block still has a finding with no recorded verdict (a pending adopted item has one, so it is not such a leftover), do not take this exit yet — go back to 2-1.
5. **LGTM-equivalent twice in a row on the SHA it leaves from, with conditions (1, 4, 5) true and requesting-code-review-empty on that same SHA** → Step 3. Pending adopted items are not batched on this exit: a push would restart the two LGTM count. Settle them per the **Exit batch**'s no-batch case.
    - LGTM-equivalent here means the round left no blocking accepted finding from any reviewer, requesting-code-review included — no findings, every finding `reject`, or only non-blocking accepts, which are recorded and not fixed on this round — not that condition 3's suppressed listing is empty.
    - requesting-code-review-empty means condition 6 holds on that SHA: no requesting-code-review finding from this round's identity without a recorded verdict. A leftover with no recorded verdict bars this exit the same way an entry no recorded pair covers bars Clean.
   - This exit applies only where full Clean was never measured on that SHA — e.g. a reject history exists, or a prior round was non-clean — and never authorizes a second request after a measured full Clean.
   - This is the stricter exit `using-dude`'s **Loop convergence** allows on top of clean, and being stricter it carries clean's conditions 1, 4 and 5 too — a red check, base drift, or a conflict all mean this doesn't hold either.
6. **A non-clean stopping condition in `using-dude`'s Loop convergence fires** → stop and hand the user the decision. Where this round's requesting-code-review block still has a finding with no recorded verdict (a pending adopted item has one, so it is not such a leftover), do not take this exit yet — go back to 2-1.

**Exit batch.** On a Clean exit (row 1) with pending adopted items, and only if `<skill-dir>/scripts/exit-batch-record.sh check` answers `NO-BATCH` and fewer than five rounds have run, drop the stale ones, then run the `implement-work` judge-records check (`check-judge-records.sh` in that skill's `scripts/` dir) from `<path>`; on any line other than `OK` run no batch and post every pending item as left unfixed with the reason it was not applied, then go to Step 3. That script's header is the single source for what each line means. Where the check passes, mark the batch with `<skill-dir>/scripts/exit-batch-record.sh set`, then fix the rest on the discipline a round's fixes take (2-3), as one commit and one push, post their states per **Posting** (fixed with the sha, withdrawn with the reason), and go back to 2-1 rather than Step 3: the batch's round reads the whole PR range like any round, and the Clean it reaches is judged on the new tip. If every item is dropped, push nothing (the mark is still set: the run batched): post the withdrawn lines and go to Step 3. A second attempt — including a re-entry through the row-6 loop — answers `ALREADY-BATCHED` at that pre-push gate and is refused: run no batch and post every pending item as left unfixed with the reason it was not applied, then go to Step 3. Where the mark answers `ALREADY-BATCHED` or the next round would be the sixth, run none: post every pending item as left unfixed with the reason it was not applied, then go to Step 3. The per-task reviews and the tail review of `subagent-driven-development` are out of scope for this wiring: they keep no judge pair and take no verification step here. Every other way into Step 3 — row 5's exit, the Clean exit without a batch, and a 2-1 that requested nobody — posts the same way, immediately before Step 3, whether or not the round had a finding.

A round here is one 2-1 → 2-2 → 2-3 cycle per `using-dude`'s **Loop convergence**, whether or not it entered the clean judgment; a check confirmed and the fix it forces sit inside that same round rather than starting a new one. Two findings are the same one when a later round makes the same claim about the same place, whichever reviewer raises it — and, for a round that went non-clean on a check, when both the check and the cause behind it are what a previous round's fix already targeted.

## Step 3: Finish

Once Step 2 exits clean, re-confirm the six conditions on the SHA it leaves from — measuring only, fixing nothing, on either value of ready-on-clean. Without this, Clean can go stale with no push at all: requesting a review is itself an action, and the check-run it starts can still fail after Step 2 already judged clean.

Call `<skill-dir>/scripts/recheck-pr.sh <owner> <repo> <pr-number> <sha> <base>` with that SHA, the base Step 1 most recently resolved, and this run's recorded suppressed pairs — each such finding's `review` and `location`, the two fields condition 3 reads. It measures in a fixed order — the head is still that SHA, the checks watched until they settle, condition 3's two listings read as that condition reads them, then base and mergeability — prints each stage's exit status and output, and ends on `RECORDED met <sha>` or `RECORDED unmet <sha>`: whether everything a machine can judge held. Three judgements stay here:

- every conclusion its watch stage printed passes, or that stage exited 5 — the script reports conclusions and never judges them, as in Step 1;
- condition 2 — read only once the script has returned;
- condition 6.

The re-confirmation holds only on `RECORDED met` with all three. Keep the re-confirmed measured-tip SHA and values (the review comment id and the verdict comment id, each included where one was posted), with what the script printed, in the report to the caller. Carry all rounds' judge record identities (each round's judge-input/verdict pair) there too, beside the measured-tip SHA. Anything short of that, and anything that needs fixing here, takes the third terminal state instead: report what was found and where the PR and branch stand, and stop — fixing at this point would flip the PR to a state nobody has actually reviewed.

Otherwise branch on the ready-on-clean flag Step 0 recorded:
- **ready-on-clean = yes**: mark the PR ready with `<skill-dir>/scripts/mark-ready.sh <owner> <repo> <pr-number>` — the only way this flow marks a PR ready. **Never mark it ready by any other means**: that marks the PR ready with no re-confirmation recorded, or on one about a commit the PR no longer points at. On `READY <n>`, Claude's LGTM is a comment, not a formal approval, so a branch-protection rule requiring an approving review may still block merge — flag that to the user, since a human approver may be needed. On `STOP <slug>`, take the third terminal state: report the slug and where the PR stands.
- **ready-on-clean = no**: report that CI and review are clean.

**This flow has three terminal states: ready, draft, and handed back to a person.** **None of them is Escalation, and none of them calls `plan-work`**: a conflict, a drifted base, or a finding only a person can settle has not touched the agreed design, so the question re-approval asks — which part of the design this undoes — has no honest answer there.

Either way, the run ends here. Everything depending on the merge belongs to a person — report it as hand-over and act on none of it:
- **the parent issue**, whenever one backs this sub-issue: GitHub doesn't close a parent when its children close, so report the sub-issue's state as of now, and if it's the last one open, that the parent becomes closable on this merge — then leave it;
- **the workspace and the branch**, both outliving this run — name the path 0-3 reused or attached, and the branch;
- **the next sub-issue**, when children remain open — say which.

Carrying on into the next one would do `implement-work`'s job with none of its gates. The one exception is an explicit instruction already in the chat covering what comes after — and even then this run still ends here: what that licenses is starting the next run through its own entry and gates, not extending this one.

## Escalation

The single source is `using-dude`'s **Escalation**; this phase is not an exception to it. Hand `plan-work`'s entry the three things it asks for: the finding — what it showed, and which part of the agreed design it undoes; the branch name; and the branch's state — whether it's pushed, and the `<PR>` this run was driving. Add where the review had got to: the round the finding surfaced on, what was already fixed and pushed, and each pending adopted item with its fix text and recorded SHA, unapplied, its planned line still on the PR. Leave the PR as it is — don't close it, and don't change its draft state.
