---
name: implement-work
description: Use to implement one PR-sized task.
---

# Implement Work

## Entry

- Take one PR-sized task here: a sub-issue, an issue fitting a single PR, or a request of that size.
- Send work larger than one PR, or a design not yet agreed, back to `plan-work`'s **Entry**, since splitting is a design decision.

## Binding `<branch>`

- Bind one concrete name here, before **Isolation** reads it.
- Take the first rung that applies:

1. **The caller named one** — a direct invocation, or a hand-off carrying a name. The name is the answer: use it verbatim, never search.
2. **The task carries one** — an item returned from `plan-work` with its design invalidated names its branch in the sub-issue body, per its **Output contract**. The name is the answer: use it verbatim, never search.
3. **Neither** — derive `<issue-number>-<slug>` where an issue backs the task, `<slug>` where none does. `<slug>` is a short kebab-case description of the change.

- Never search a rung-3 name with no issue behind it, since there is no number to build a prefix from.
- Give a rung-3 name with an issue behind it one search by that issue number through `scripts/resolve-branch.sh <issue-number>`, since it prints every branch already cut for that issue, one name per line.
- Count that search's lines: none means `<branch>` is the name derived.
- Count of exactly one means `<branch>` becomes that branch, and the run below resumes on it.
- Count of two or more means stop and ask, since which line of work to carry on is a human call.
- Put the workspace on this exact name, whatever creates it, since a tool decorating the handed name leaves a branch this search cannot find and the next session opens a second branch for the same task.

## Isolation

- Establish isolation before drafting the plan, since the plan file has to live inside the workspace the execution method reads it from.
- Use `superpowers:using-git-worktrees`.
- Establish a verified baseline there.
- Look before creating on resumption, since that skill reads the current directory for existing isolation only and assumes a new branch on creation.
- Read the one-line answer from `tools/attach-workspace.sh <branch> <path>`.
- On `REUSE <path>`, use the workspace as-is, since it already carries `<branch>`.
- On `ATTACHED <path>`, use the new workspace tracking the branch, since no workspace existed but the branch did locally or on the remote.
- On `CREATE`, create the branch from the base **Base branch** settles, since no branch exists anywhere.
- Check the remote before giving up, since creating afresh where a branch already exists remotely strands that pushed work under a diverged history with no recovering it.

## Base branch

- Apply this section only on `CREATE` above.
- Branch a task with no tracking issue from the default branch.
- Apply everything below only when an issue backs the task.
- Resolve the base with `scripts/resolve-base.sh <issue-number>`, since it reads the prerequisite from the one `Blocked-By: #N` line `plan-work`'s **Splitting into sub-issues** writes in the issue body and settles the base from the state of the PR closing that prerequisite.
- Take that PR's head on `OPEN`, and the default branch on `MERGED`, since both are fetched first so the cut branch contains what it is meant to.
- On `NEED <token>...`, read the facts it names as `references/facts.md` defines them, write them to one facts file, and run it again with `--facts <file>` added, for as long as it asks.
- On `BASE <branch>`, cut the new branch from `origin/<branch>`, never the bare name.
- On `STOP <slug>`, stop and report why the task cannot start, or ask which base to use, per the printed reason.
- Record a non-default base as one `Base-Branch: <base>` trailer line on this task's first commit, using the bare branch name, never an `origin/` prefix.
- Record nothing when branching from the default branch.

## Alternatives

- Run this after **Isolation** and before **Plan gate**.
- Run this on the small-change lane too, then go to **Execution**.
- Take the task's own purpose as the purpose: sub-issue, single-PR issue, or request.
- Skip on an unnamed purpose: do not invoke, note the skip, and continue.
- Take the base **Base branch** would settle as the read-root, resolved on `REUSE` and `ATTACHED` too and defaulting to the default branch for a task with no issue, handed as `origin/<base>` fetched to its current tip.
- Otherwise invoke `propose-alternatives` once with that purpose, that read-root, and the current artifact.
- Leave its compare, one review-findings pass, and ask-person continue-vs-revisit to that procedure.
- Continue on its return.
- Take **Escalation** with the finding on revisit design, never **Plan gate**.

## Plan gate

- Skip this gate outright on the small-change lane in `using-dude`'s **Workflow selection**.

1. Read the task. A sub-issue carries its own body plus a link to the parent's design comment; an issue that fits one PR carries its own comment; a request with no issue is the input, with whatever `plan-work` left in chat per its **Output contract**.
2. Dispatch a drafter at fresh context with `superpowers:writing-plans`. The brief carries references to where step 1 found the design — never the design itself — plus the workspace path and the branch. The worker drafts the plan and returns its path; it never implements. What this gate takes back has been through that skill's own self-review. The plan lives in the workspace, git-ignored and never committed.
3. Dispatch `review-plan` on the implementation plan, fold every accepted finding except one that invalidates the agreed design — which is not folded at all — then re-run `review-plan`, handing over the previous pass's findings.
4. Leave by exactly one of three exits: **Clean** per `using-dude`'s **Loop convergence** goes to **Execution**; **Design invalidated** by a Critical finding takes **Escalation**; **Stalled** on a non-clean stopping condition with a surviving blocking finding stops for the user, per that rule. A round is one `review-plan` pass and the fold-in that follows it; two findings are the same when they fault the same step for the same reason.

## Execution

- **Default** goes to `superpowers:subagent-driven-development`.
- **Inline** — the person chose inline execution, or no subagent tool is available — goes to `superpowers:executing-plans`.
- **Manual** is the fitting method on the small-change lane in `using-dude`'s **Workflow selection**, and an exception needing a named reason anywhere else.
- Say which method runs and why.
- Inline only trivially small independent changes, since delegation pays only when a task covers the hand-off.
- Take no refactoring the task did not ask for.
- Leave integration and the final whole-branch review to the completion gate, since its own review is the verdict this flow stands on.
- Where the method kept a ledger, collect every line carrying its `Ruling:` marker into **Report**, each with what it costs if wrong.
- Hand the lines carrying its `Ruling:` marker and its deferred-minor marker (`minor (deferred)`) to step 3 unchanged.
- Run the method's own Finish except its deletion of the plan's workspace (the directory holding its ledger), since step 3 hands the ledger's lines every round and that directory stays until this flow ends.
- Delete that directory after **Report** holds the rulings and, on the normal exit, after **Hand off**.

## Completion gate

- Verify against the entry artifact every round, then run `simplify-code`, then `review-code`, since one round is that sequence.
- Stop the loop per `using-dude`'s **Loop convergence**.
- Exit normally only on a round that changed nothing with step 3 clean and absorb answering `UP-TO-DATE`.
- Count one pass of steps 1-5 as one round.
- Count a later round bringing back what an earlier round already tried to resolve as the same finding: the same claim about the same location, or the same unmet completion criterion.

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

- Push the branch under its own name.
- Open the draft PR through `superpowers:finishing-a-development-branch` Option 2.
- Keep the dude delta to only this: always draft.
- Carry a closing keyword (`fixes`/`closes`/`resolves`) in the body on the issue this work resolves, qualified as `owner/repo#NNN` where that issue lives in another repository.
- Take the base whatever **Base branch** would settle.
- Leave a PR already open on the branch as the deliverable, with its status as is.
- Ask which repository the draft PR targets where origin is a fork or has another remote, offering origin's own first.
- Name `pr-to-ready` as the next entry without invoking it.

## Report

- Report whether the small-change lane was taken.
- Report the one-line basis when it was taken.
- Report whether `propose-alternatives` was invoked or skipped, and why.
- Report the execution method chosen, and why.
- Report the base the task was cut from, and which of **Base branch**'s outcomes chose it.
- Report the `review-plan` rounds on the detailed plan, and the final verdict.
- Report the `review-code` verdict, and any blocking finding left open.
- Report the completion gate's rounds, and the condition it exited on.
- Report the execution method's rulings, each with what it costs if wrong, or that it made none.
- Report the base absorbed, how it was re-resolved, and what the absorb answered on the final round.
- Report the completion criteria checked against the entry artifact: which were met, and any gap with how it was routed.
- Report the concrete checks run, and any that could not be.
- Report what changed and why.
- Report the pushed branch and the draft PR — found or opened by this run — with `pr-to-ready` named as the next entry.
- Report assumptions made, and areas needing manual review.

## Escalation

- Send a Critical finding invalidating the agreed design back to `plan-work`'s **Entry** for re-approval per `using-dude`'s **Escalation**, since neither the plan gate nor the completion gate is an exception in this skill.
- Hand over the branch on this exit: its name, whether it is pushed, and any PR open on it.
- Keep the round's commits on the branch where the finding surfaced in the completion gate, since the gate commits before taking either exit.
