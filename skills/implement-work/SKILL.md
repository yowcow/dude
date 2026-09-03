---
name: implement-work
description: Use to take one PR-sized task — a sub-issue, an issue that fits a single PR, or a request of that size — all the way to a draft PR on a pushed branch of verified commits. Triggers on "implement this sub-issue", "start implementing", "work through this task", "run the completion gate", "take this to a branch".
---

# Implement Work

There is no plan yet.

This skill holds two gates: one on the detailed plan, before any code, and the completion gate at the end. It does not own the PR-side loop — the draft PR it opens at the end is where `pr-to-ready` takes over with its own completion path, and neither gate here is re-entered from there.

## Orchestration model

**This skill dispatches no workers of its own.** It runs in the main loop as the orchestrator; every worker in this flow is dispatched by a sub-skill it calls — `review-plan`, the execution method, `simplify-code`, `review-code` — each declaring its own fan-out, so add none here.

The orchestrator owns the task, the workspace, both gates, the execution-method choice, every commit, and the hand-off, and decides when a gate is clean. Workers do bounded, single-task work and hand back — never an objective spanning more than one task, and never a gate declared clean by a worker.

## Entry

One PR-sized task:

- a sub-issue,
- an issue that fits a single PR,
- or a request of that size.

Work larger than one PR, or a design not yet agreed, goes back to `plan-work`. Don't split it here — splitting is a design decision.

### Binding `<branch>`

**Isolation** below reads `<branch>` as already known, so bind it to one concrete name here, before that ladder runs. Take the first rung that applies:

1. **The caller named one** — a user invoking this skill directly, or a hand-off that carries a name.
2. **The task carries one** — an item that came back from `plan-work` with its design invalidated names its branch in the sub-issue body.
3. **Neither** — derive a new name: `<issue-number>-<slug>` where an issue backs the task, `<slug>` where none does. `<slug>` is a short kebab-case description of the change.

**A name from rung 1 or 2 is already the answer: don't search, use it verbatim.** `plan-work`'s discard convention gives a **new** name to an item whose old branch is to be abandoned; searching by issue number there would turn up that abandoned branch and hand it to the ladder, which reuses whatever it finds — resuming on top of the very commits the invalidated design produced, which is the failure that convention exists to prevent.

A rung-3 name with no issue behind it isn't searched at all — there is no number to build a prefix from. A rung-3 name with an issue behind it gets one search, by that issue number, before it is used: run `<skill-dir>/scripts/resolve-branch.sh <issue-number>`, which prints every branch already cut for that issue — local and remote, deduplicated across both — one name per line. `<skill-dir>` here and below is this skill's own directory inside the installed plugin, `skills/implement-work/`.

Count the lines it printed: none — `<branch>` is the name just derived; exactly one — `<branch>` becomes that branch, and this is a resumed session that the ladder below attaches to; two or more — stop and ask, since which line of work to carry on is a human call.

Whatever creates the workspace has to put it on this exact name. A tool that decorates the name it is handed — prefixing its own worktree branches, say — leaves a branch this search cannot find, so the next session derives a fresh name and opens a second branch for the same task.

## Isolation

Establish this **before drafting the plan**: the plan file has to live inside the workspace the execution method will read it from, and a workspace created afterwards would not contain it — a new working tree gets the tracked content, not ignored scratch files.

Use `superpowers:using-git-worktrees`, then establish a verified baseline there.

The contract behind the `Base-Branch:` trailer, the ladder that resolves the default branch, and how each reader settles a base from the prerequisite's PR state all live in `<skill-dir>/references/base-branch.md`; why the scripts below test what they test the way they do is in each script's own header comment instead.

That skill detects existing isolation from the current directory only, and its creation step assumes the branch is new. So on resumption, look before creating: run `<skill-dir>/scripts/attach-workspace.sh <branch> <path>` and read its one-line answer.

- `REUSE <path>` — a worktree already carries `<branch>`; use it as-is.
- `ATTACHED <path>` — no worktree existed, but the branch did, locally or (fetched first) only on the remote; a new workspace now tracks it. Checking the remote before giving up matters here: creating a branch afresh where one already exists remotely would strand that pushed work under a diverged history, and force-push is barred, so there is no recovering it.
- `CREATE` — no branch exists anywhere; create it normally, from the base that **Base branch** below settles.

### Base branch

Only `CREATE` above needs this — `REUSE` and `ATTACHED` attach to a branch that already exists.

A task with no tracking issue — the chat-only entry — has no relation to read at all: branch from the default branch. Everything below applies only when an issue backs the task.

Run `<skill-dir>/scripts/resolve-base.sh <issue-number>`. It reads the prerequisite from the issue's native `blockedBy` relation, never from issue-body prose, and settles the base from that prerequisite's PR state: `OPEN` → that PR's head; `MERGED` → the default branch — both fetched first, so the branch you cut actually contains what it's meant to. Read its one-line answer: `BASE <branch>` — cut the new branch from `origin/<branch>`, the remote-tracking ref the script has just fetched, and **not** from the bare name. `STOP <reason>` — no prerequisite's PR exists at all, more than one prerequisite or PR reference, or a prerequisite closed without merging: stop, and either report why the task can't start or ask a person which base to use, per the reason printed.

**Record a non-default base** as a single `Base-Branch: <base>` line in the trailer block of this task's **first** commit — `<base>` the bare branch name, no `origin/` prefix and no `refs/heads/` path. Branching from the default branch records nothing.

If the verified baseline contradicts what the plan assumes — an existing failure, missing tooling — go back to **Plan gate** before starting tasks, or take **Escalation** where the small-change lane in `using-dude`'s **Workflow selection** skipped that gate.

## Plan gate

The small-change lane in `using-dude`'s **Workflow selection** skips this gate outright.

1. Read the task. Where the design lives depends on the entry: a **sub-issue** carries its own body plus a link to the parent's design comment; an **issue that fits one PR** carries its own comment; a **request with no issue** is itself the input, together with whatever `plan-work` left in chat.
2. Draft the detailed plan with `superpowers:writing-plans`. What this gate takes from it is a plan that has been through that skill's own self-review — not the file the moment it lands. It goes in the workspace, git-ignored, and is never committed or published. **Don't follow that skill onward into whatever it moves on to next; what runs after this gate is settled here.**
3. Dispatch `review-plan` with the target declared as the implementation plan. Fold every accepted finding in yourself — except one that invalidates the agreed design, which is not folded in at all: stop and take the **Design invalidated** exit below. Then re-run `review-plan`, handing over the record of the previous pass so it doesn't re-litigate rejected findings.
4. Leave by exactly one of three exits:
   - **Clean** — no blocking finding → **Execution**.
   - **Design invalidated** — a Critical finding that undoes the agreed design → take **Escalation**.
   - **Stalled** — one of `using-dude`'s **Loop convergence** non-clean stopping conditions fired while a blocking finding that doesn't invalidate the design survives → stop and let the user decide, per that rule. A round is one `review-plan` pass on this plan and the fold-in that follows it; two findings are the same when they fault the same step for the same reason.

## Execution

Choose the method and say which you chose and why — explicitly, never by drift:

- **Default** → `superpowers:subagent-driven-development`.
- **A separate session picking the plan up later** → `superpowers:executing-plans`.
- **Manual** is the fitting method on the small-change lane in `using-dude`'s **Workflow selection**, and an exception that needs a reason anywhere else. Off that lane, try first to replan the work into tasks that can each be verified on their own; do it yourself only when it genuinely won't split, or when workers aren't available. Name the reason.

Delegate and don't restate: worker dispatch, model selection, the ban on parallel implementers, per-task review, the fix loop, and progress tracking all belong to `superpowers:subagent-driven-development`; TDD to `superpowers:test-driven-development`; parallel workers, for independent fact-finding only, to `superpowers:dispatching-parallel-agents`.

Two judgements stay here: delegation only pays when a task is big enough to cover the hand-off, so inline trivially small independent changes; and don't take on refactoring the task didn't ask for.

**The execution method does not carry the work into integration.** Its own procedure ends by presenting integration options; the completion gate runs first, and **Hand off** owns the terminal step. What that cuts is the transition only — the method's own cleanup before it, such as removing its scratch workspace, still runs.

## Completion gate

Add only what the execution method left undone. A round is one pass of steps 1-5, and this loop stops per `using-dude`'s **Loop convergence** — step 6 orders those conditions against this gate's own. A finding is the same one when a later round brings back what a previous round already tried to resolve: the same claim about the same location, or the same unmet completion criterion.

1. **Verify** — `superpowers:verification-before-completion`. Its requirements checklist reads **the task's own entry artifact**, not the detailed plan: a sub-issue's purpose, scope boundary, and completion criteria; an issue's own comment; or the request itself where no issue tracks the work. The plan is a transcription of that artifact, so checking against it confirms only the transcription — and on the small-change lane in `using-dude`'s **Workflow selection** there is no plan to check against at all.
   - **The scope boundary is part of that source, not commentary on it.** What it excludes never becomes a checklist row, so an exclusion cannot come back as a gap.
   - **An unmet criterion routes on one test: does meeting it require touching what the scope boundary excludes?** No → it is this task's work, so implement it in this round. Yes → don't implement it; record it and leave by step 6's first exit. Criteria that contradict each other, or the agreed design, are outside this test — no checklist can be built from them at all — and take `using-dude`'s **Escalation** by that route, recorded and exited the same way.
2. **Simplify** — `simplify-code` on the recent diff only. No execution method has a simplification pass, so this is the gate's main job.
3. **Review** — run `review-code`. The only basis for declaring this gate clean is a verdict it produced itself: any review an execution method may have run belongs to that method's own procedure, so its scope and verdict can't be checked from here.
4. **Commit** the round's work in the same round that produced it, so the tree is clean before either exit below hands the branch onward — **Hand off** pushes it, and a push carries only commits, while **Escalation** hands `plan-work` a branch name that re-approval judges by what it contains; either way, anything left uncommitted is simply absent from what the next flow reads. Confirm it worked by running `<skill-dir>/scripts/check-clean.sh` and reading its exit status — 0 is clean, non-zero is dirty and prints what is pending; don't leave this step while it reports dirty. A byproduct of step 1's checks belongs in `.gitignore`; the byproduct itself is never committed. A round that changed nothing commits nothing, and anything you can't account for as this round's own work stops the gate and goes to the user rather than being swept in.
5. **Absorb the base** — run `<skill-dir>/scripts/absorb-base.sh <branch> <base>`, with `<base>` **re-resolved now** rather than the base the branch was cut from: run `<skill-dir>/scripts/resolve-base.sh <issue-number>` again and take the bare name it prints after `BASE`, handling a `STOP` as **Base branch** does; a task with no issue behind it uses the default branch. **Base branch**'s `origin/` prefix belongs to cutting a branch and is wrong here — this step fetches the base itself, so the bare name is what it wants, and an `origin/`-prefixed one sends the fetch after `refs/heads/origin/<base>` and stops the gate reporting a base that is missing when it is not. That is the answer to "what will this merge into", which is a different question from the base of the range `review-code` reviews; `references/base-branch.md` holds why the two may differ, and why this sits here rather than where the branch was cut. It comes after Commit because the first round can still hold the execution method's uncommitted changes, and `git merge` requires a clean tree. Without this step the gate verifies the base snapshot the branch was cut from: every check passes, `pr-to-ready` gets CI green and the review clean, and a combination that only breaks with both sides present lands on the default branch having been verified by nobody. Branch on the one line it prints:
   - `UP-TO-DATE` — the base is already in and nothing changed. This is what makes step 6's normal exit mean the last verify ran against the tree that will merge.
   - `MERGED <sha>` — the base is in, and something changed, so step 6 sends the round back.
   - `CONFLICTED <path>...` — the conflict is left in the tree deliberately. Resolve the hunks yourself in this workspace, then commit the resolution with `<skill-dir>/scripts/commit-merge.sh`: `COMMITTED <sha>` is done, `UNRESOLVED` or `MARKERS` names what is still wrong with the tree and has to be fixed before it will commit, and its own `STOP <slug>` is handled like the one below — a commit the repository refused is not a tree still holding a conflict, so re-scanning it for one gets nowhere. **Where the resolution doesn't settle — both sides changed the same place with different intent, or taking one would silently drop what the other meant — restore the pre-merge tree and stop the gate**, handing the user the paths and what was ambiguous. This is step 4's rule about work you can't account for, in this step's own terms: it adds no row to the table below, and it is not **Escalation**, because nothing has invalidated the agreed design.
   - `STOP <slug>` — stop and report, or ask, according to the slug.
6. Take the first row that applies:

   | # | Condition | Where it goes |
   | --- | --- | --- |
   | 1 | **The agreed design is what has to change** — `review-code` reported a Critical finding that invalidates it, or step 1 recorded a criterion that the scope boundary puts out of reach, or one that contradicts another criterion or the agreed design | Stop the gate and return to `plan-work`, per **Escalation** |
   | 2 | **`review-code` stopped short of clean with blocking findings open**, per `using-dude`'s **Loop convergence** | The whole gate halts here, whatever else changed. Report the open findings and let the user decide. Don't loop back, and don't re-invoke `review-code` |
   | 3 | **This gate's own rounds hit one of those non-clean conditions** — the gate as an ordinary loop, rather than as the receiver of `review-code`'s stop | Stop and hand the decision over the same way |
   | 4 | **Any step of this round changed something** — code, or a base absorbed by step 5 | Back to step 1 — verification and simplification have to run against the tree as it now stands |
   | 5 | **Nothing changed and step 3 came back clean** — the review clean, and step 5 answering `UP-TO-DATE` | **Hand off** — the loop's only normal exit, and *clean* per `using-dude`'s **Loop convergence** |

   The order is what makes this correct: a `review-code` that stopped short of clean still applied and verified its fixes first, so rows 2-4 can be true at once, and row 1 can surface on any round — in any other order the gate would loop where it has to stop, or carry a design-invalidating finding forward. The rows differ in kind, not degree — a design-invalidating finding, a stopped review, this gate's own stall, more work to do, and done — so per `AUTHORING.md`'s rule 3 the table stays whole rather than compressed to an invariant.

## Hand off

The deliverable is a **draft PR** on a pushed branch of verified commits — exactly what `pr-to-ready` takes as its entry. Once the completion gate takes its normal exit, push and then open the PR, in that order.

Push the branch to `origin` under its own name, unconditionally. The push is what turns the branch into a deliverable rather than local state: opening a PR needs a remote ref, so an unpushed branch leaves the next flow nothing to enter on — in a later session, or a checkout that never held the branch.

Then call `<skill-dir>/../pr-to-ready/scripts/ensure-draft-pr.sh <branch> <title> <body-file>` once — the sibling skill's script, reached by relative path because this skill holds no copy of it. It looks for a PR already on `<branch>` and creates one only when none is found, resolving the base itself at that point alone. Branch on the one line it prints:

- `PR <n> found draft=<bool>` — an earlier session on this branch already opened one. Take it as the deliverable and **leave its status as it is**: a person may have marked it ready, and pulling it back to draft would take a PR out of review that nobody asked to reopen.
- `PR <n> created draft=true base=<base>` — this run opened it.
- `STOP <slug>` — no PR was opened. Report the stop, and hand the branch over regardless.

Title and body are standard Japanese (標準語), following the repo's PR template when it has one. The body carries a closing keyword (`fixes`/`closes`/`resolves`) on the issue this work resolves, fully qualified as `owner/repo#NNN` when that issue lives in another repository. The PR is always opened as a draft — nothing here has run CI or been reviewed, so nothing has yet earned a person's merge attention.

Then stop, and name `pr-to-ready` as the next entry **without invoking it**, handing it the PR's URL — that reference is its whole entry. Which flow runs next is the caller's decision, not this skill's.

- **PR creation belongs here**, and to this one point in the flow.
- **Integration goes through a PR.** Merging this branch into its base instead of handing it over would skip `pr-to-ready`, CI, and PR review entirely. If the user explicitly wants that, confirm they mean to skip the PR before doing it — this skill carries no merge procedure of its own.

## Report

- whether the small-change lane in `using-dude`'s **Workflow selection** was taken, and the one-line basis if it was
- the execution method chosen, and why
- the base branch the task was created from, and which of **Base branch**'s outcomes chose it
- the `review-plan` rounds run on the detailed plan, and the final verdict
- the completion gate's `review-code` verdict, and any blocking finding left open
- the completion gate's rounds, and the condition it exited on
- the base absorbed, how it was re-resolved, and what the absorb answered on the final round
- the completion criteria checked against the entry artifact: which were met, and any gap with how it was routed
- the concrete checks run, and any that couldn't be
- what changed and why
- the pushed branch and the draft PR — its URL, and whether this run opened it or found one already open — with `pr-to-ready` named as the next entry
- assumptions made, and areas needing manual review

## Escalation

Per `using-dude`'s **Escalation**: a Critical finding that invalidates the agreed design goes back to `plan-work` for re-approval, and this skill is no exception — not in the plan gate, and not in the completion gate.

What this flow hands over is the branch: its name, whether it is pushed, and any PR open on it — this flow opens one only at **Hand off**, which an escalating run never reaches. `plan-work`'s **Entry** says what it does with that. Where the finding surfaced in the completion gate, the branch already carries the round's commits, since the gate commits before taking either exit.
