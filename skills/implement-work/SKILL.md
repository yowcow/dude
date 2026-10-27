---
name: implement-work
description: Use to implement one PR-sized task.
---

# Implement Work

## Entry

One PR-sized task: a sub-issue, an issue that fits a single PR, or a request of that size. Work larger than one PR, or a design not yet agreed, goes back to `plan-work` — splitting is a design decision.

## Binding `<branch>`

Bind one concrete name here, before **Isolation** reads it. Take the first rung that applies:

1. **The caller named one** — a direct invocation, or a hand-off carrying a name. The name is already the answer: use it verbatim, never search.
2. **The task carries one** — an item returned from `plan-work` with its design invalidated names its branch in the sub-issue body. The name is already the answer: use it verbatim, never search.
3. **Neither** — derive `<issue-number>-<slug>` where an issue backs the task, `<slug>` where none does. `<slug>` is a short kebab-case description of the change.

A rung-3 name with no issue behind it is never searched — there is no number to build a prefix from. A rung-3 name with an issue behind it gets one search by that issue number through `scripts/resolve-branch.sh <issue-number>`, which prints every branch already cut for that issue, one name per line. Count the lines: none — `<branch>` is the name just derived; exactly one — `<branch>` becomes that branch, and the run below resumes on it; two or more — stop and ask, since which line of work to carry on is a human call.

Whatever creates the workspace has to put it on this exact name: a tool that decorates the name it is handed leaves a branch this search cannot find, so the next session derives a fresh name and opens a second branch for the same task.

## Isolation

Establish this before drafting the plan: the plan file has to live inside the workspace the execution method reads it from.

Use `superpowers:using-git-worktrees`, then establish a verified baseline there. That skill reads the current directory for existing isolation only and assumes a new branch on creation, so on resumption look before creating: `tools/attach-workspace.sh <branch> <path>` answers in one line. `REUSE <path>` — a workspace already carries `<branch>`; use it as-is. `ATTACHED <path>` — no workspace existed but the branch did, locally or on the remote, and a new workspace now tracks it. `CREATE` — no branch exists anywhere; create it from the base **Base branch** settles. Checking the remote before giving up matters: creating afresh where a branch already exists remotely strands that pushed work under a diverged history, with no recovering it.

## Base branch

Only `CREATE` above needs this. A task with no tracking issue branches from the default branch; everything below applies only when an issue backs the task.

`scripts/resolve-base.sh <issue-number>` reads the prerequisite from the one `Blocked-By: #N` line `plan-work` writes in the issue body, and settles the base from the state of the PR closing that prerequisite: `OPEN` takes that PR's head, `MERGED` takes the default branch — both fetched first, so the cut branch contains what it is meant to. On `NEED <token>...`, read the facts it names as `references/facts.md` defines them, write them to one facts file, and run it again with `--facts <file>` added, for as long as it asks. Read its one-line answer: `BASE <branch>` cuts the new branch from `origin/<branch>`, never the bare name. On `STOP <slug>`, stop and report why the task cannot start, or ask which base to use, per the printed reason.

Record a non-default base as one `Base-Branch: <base>` trailer line on this task's first commit — the bare branch name, never an `origin/` prefix. Branching from the default branch records nothing. The trailer contract lives in `references/base-branch.md`.

## Alternatives

After **Isolation**, before **Plan gate**. The small-change lane still runs this, then **Execution**.

Purpose is the task's own purpose: sub-issue, single-PR issue, or request. An unnamed purpose means skip — do not invoke, note the skip, and continue. Read-root is the base **Base branch** would settle — resolved on `REUSE` and `ATTACHED` too, and the default branch for a task with no issue — handed as `origin/<base>`, fetched to its current tip. Otherwise invoke `propose-alternatives` once with that purpose, that read-root, and the current artifact. Compare, the one review-findings pass, and the ask-person continue-vs-revisit are propose-alternatives's own procedure; on its return, continue; on revisit design, take **Escalation** with the finding and do not proceed to **Plan gate**.

## Plan gate

The small-change lane in `using-dude`'s **Workflow selection** skips this gate outright.

1. Read the task. A sub-issue carries its own body plus a link to the parent's design comment; an issue that fits one PR carries its own comment; a request with no issue is itself the input, with whatever `plan-work` left in chat.
2. Dispatch a drafter at fresh context with `superpowers:writing-plans`. The brief carries references to where step 1 found the design — never the design itself — plus the workspace path and the branch. The worker drafts the plan and returns its path; it never implements. What this gate takes back has been through that skill's own self-review. The plan lives in the workspace, untracked and never committed.
3. Dispatch `review-plan` on the implementation plan, fold every accepted finding except one that invalidates the agreed design — which is not folded at all — then re-run `review-plan`, handing over the previous pass's findings.
4. Leave by exactly one of three exits: **Clean** per `using-dude`'s **Loop convergence** goes to **Execution**; **Design invalidated** by a Critical finding takes **Escalation**; **Stalled** on a non-clean stopping condition with a surviving blocking finding stops for the user, per that rule. A round is one `review-plan` pass and the fold-in that follows it; two findings are the same when they fault the same step for the same reason.

## Execution

- **Default** goes to `superpowers:subagent-driven-development`.
- **Inline** — the person chose inline execution, or no subagent tool is available — goes to `superpowers:executing-plans`.
- **Manual** is the fitting method on the small-change lane in `using-dude`'s **Workflow selection**, and an exception needing a named reason anywhere else.

Say which method runs and why. Delegation only pays when a task covers the hand-off, so inline trivially small independent changes; take on no refactoring the task did not ask for. The method does not carry the work into integration, and its final whole-branch review does not run here — the completion gate's own review is the verdict this flow stands on. Where the method kept a ledger, collect every line carrying its `Ruling:` marker into **Report**, each with what it costs if wrong, and hand the lines carrying its `Ruling:` marker and its deferred-minor marker (`minor (deferred)`) to step 3 unchanged. Run the method's own Finish except its deletion of the plan's workspace (the directory holding its ledger): step 3 hands the ledger's lines every round, so that directory stays until this flow ends, then delete it — after **Report** holds the rulings and, on the normal exit, after **Hand off**.

## Completion gate

One round is verify against the entry artifact, every round, then `simplify-code`, then `review-code`; the loop stops per `using-dude`'s **Loop convergence**. The only normal exit is a round that changed nothing with step 3 clean and absorb answering `UP-TO-DATE`. A round is one pass of steps 1-5; a finding is the same one when a later round brings back what an earlier round already tried to resolve: the same claim about the same location, or the same unmet completion criterion.

1. **Verify.** The checklist reads the task's own entry artifact, never the detailed plan: a sub-issue's purpose, scope boundary, and completion criteria; an issue's own comment; or the request itself where no issue tracks the work. Run it every round, even when nothing changed this round, and keep the verdict in the main loop — never dispatch it. The scope boundary is part of that source, not commentary on it: what it excludes never becomes a checklist row. An unmet criterion routes on one test — does meeting it require touching what the boundary excludes? No: it is this task's work, so implement it in this round. Yes: do not implement it; record it and take the design-invalidated exit in step 6. Criteria that contradict each other or the agreed design take `using-dude`'s **Escalation** by the same route, recorded the same way.
2. **Simplify.** Run `simplify-code` on the recent diff only.
3. **Review.** Run `review-code`, handing it the requirements it judges against: the entry artifact as step 1 reads it, scope boundary included, with the detailed plan travelling only as that artifact's transcription where one was drafted — and where the execution method kept a ledger, the lines carrying its `Ruling:` marker and its deferred-minor marker (`minor (deferred)`) unchanged, each ending fixed or declined with the reason, or open with the blocking findings. The only basis for declaring this gate clean is a verdict this step produced itself.
4. **Commit** the round's work in the round that produced it, so the tree is clean before either exit below hands the branch onward. Confirm it with `tools/check-clean.sh` and do not leave this step while it reports dirty. A byproduct of step 1's checks stays out of version control and is never committed. A round that changed nothing commits nothing, and anything unaccounted for as this round's own work stops the gate instead of being swept in.
5. **Absorb the base.** Run `scripts/absorb-base.sh <branch> <base>` with the base re-resolved now — `scripts/resolve-base.sh` again with every fact read afresh, `NEED` and `STOP` handled as **Base branch** does, the default branch where no issue backs the task — and the bare name, never an `origin/` prefix. It comes after Commit because the first round can still hold the execution method's uncommitted changes. Branch on its one line: `UP-TO-DATE` — the base is already in, so the last verify ran against the tree that will merge; `MERGED <sha>` — the base is in and something changed, so step 6 sends the round back; `CONFLICTED <path>...` — the conflict stays in the tree: resolve it in the main loop, commit the resolution with `scripts/commit-merge.sh`, and where the resolution does not settle, restore the pre-merge tree and stop; `STOP <slug>` — stop and report, or ask, per the printed slug.

6. Take the first row that applies:

   | # | Condition | Where it goes |
   | --- | --- | --- |
   | 1 | The agreed design is what has to change — an invalidating Critical finding, a recorded out-of-reach criterion, or contradictory criteria | Stop the gate and take **Escalation** |
   | 2 | `review-code` stopped short of clean with blocking findings open | Halt here, whatever else changed. Report the open findings and let the user decide |
   | 3 | This gate's own rounds hit one of those non-clean conditions | Stop and hand the decision over the same way |
   | 4 | Any step of this round changed something | Back to step 1 |
   | 5 | Nothing changed and step 3 came back clean | **Hand off** — the loop's only normal exit, and *clean* per `using-dude`'s **Loop convergence** loop-clean |

## Hand off

Push the branch under its own name, then open the draft PR through `superpowers:finishing-a-development-branch` Option 2. The dude delta on that procedure is only this: always draft; the body carries a closing keyword (`fixes`/`closes`/`resolves`) on the issue this work resolves, qualified as `owner/repo#NNN` where that issue lives in another repository; the base is whatever **Base branch** would settle. A PR already open on the branch is the deliverable, its status left as is. Where origin is a fork or has another remote, ask which repository the draft PR targets, offering origin's own first. Then name `pr-to-ready` as the next entry without invoking it.

## Report

- Whether the small-change lane was taken, and the one-line basis if it was
- Whether `propose-alternatives` was invoked or skipped, and why
- The execution method chosen, and why
- The base the task was cut from, and which of **Base branch**'s outcomes chose it
- The `review-plan` rounds on the detailed plan, and the final verdict
- The `review-code` verdict, and any blocking finding left open
- The completion gate's rounds, and the condition it exited on
- The execution method's rulings, each with what it costs if wrong — or that it made none
- The base absorbed, how it was re-resolved, and what the absorb answered on the final round
- The completion criteria checked against the entry artifact: which were met, and any gap with how it was routed
- The concrete checks run, and any that could not be
- What changed and why
- The pushed branch and the draft PR — found or opened by this run — with `pr-to-ready` named as the next entry
- Assumptions made, and areas needing manual review

## Escalation

Per `using-dude`'s **Escalation**: a Critical finding that invalidates the agreed design goes back to `plan-work` for re-approval — not in the plan gate, and not in the completion gate, is this skill an exception.

What this flow hands over is the branch: its name, whether it is pushed, and any PR open on it. Where the finding surfaced in the completion gate, the branch already carries the round's commits, since the gate commits before taking either exit.
