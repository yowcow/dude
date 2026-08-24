# Base-Branch trailer

The `Base-Branch:` trailer is a **shared mechanism with one writer and two readers**. `implement-work` writes it when it cuts a branch; `pr-to-ready` reads it to settle `gh pr create --base`; `review-code` reads it as the base of the range it reviews. **What the trailer records is which prerequisite the branch sits on, and only that.** Whether that prerequisite is still in flight is not recorded and could not be — time passes between cutting the branch and reading the trailer. So neither reader re-derives *which* prerequisite it is; both re-read *what state it is now in*, and settle the base from that.

This file holds the contract and the reasons; the commands a skill actually runs belong in that skill's `scripts/`.

## The contract

A single `Base-Branch: <base>` line in the trailer block of the task's **first** commit. `<base>` is the bare branch name — no `origin/` prefix, no `refs/heads/` path.

Branching from the default branch records **nothing**.

## Resolving the default branch

Never guess a branch name. Three rungs, in order — `git symbolic-ref`, then `gh repo view`, then ask the user.

Each skill's own form belongs in its own `scripts/`.

## Reading the trailer back

Where a stack runs deeper than one, the nearest trailer wins.

When a trailer is found, look the prerequisite's PR up by its head branch name.

The base then follows from that state:

| trailer / prerequisite PR state | `review-code`'s `<base>` | `pr-to-ready`'s `--base` |
| --- | --- | --- |
| no trailer | the default branch | omit |
| `OPEN` | `git fetch origin <recorded>`, then `FETCH_HEAD` | `<recorded>` |
| `MERGED` | `git fetch origin refs/pull/<n>/head`, then `FETCH_HEAD` | the default branch — omit `--base`, and retarget an existing PR that still points at `<recorded>` |
| `CLOSED` without merging | **stop** | **stop** |
| no PR found | **stop** and report it | **stop** and report it |
| two or more PRs | **stop and ask** | **stop and ask** |

`<n>` is the PR number the lookup printed beside the state. The no-trailer row needs no lookup.

The last two rows both stop, and they differ in what they put to the person. No PR on the recorded branch leaves the base unknowable, so there is nothing to choose between and the run reports what it found — the same answer `implement-work`'s writer-side rule gives an unimplemented prerequisite. Two or more PRs leaves a genuine choice: the trailer already fixed *which* prerequisite this is, so what is open is which of that one branch's PR records the base should follow. That one asks.

### Why the state is re-read and the branch is not

The test this replaced asked `git ls-remote --exit-code --heads origin <recorded>` — whether the branch still exists. That is the wrong question, because nothing ties a branch's existence to its PR's state:

- `deleteBranchOnMerge` is false here, so merging never deletes the prerequisite's branch. Deleting it is a person's step, taken whenever they get round to it. So a surviving branch may be long merged, and a vanished one proves only that somebody tidied up.
- Read as "still in flight", a surviving merged branch hands `pr-to-ready` that branch as `--base`. Merging a PR into an already-merged branch puts nothing into the default branch, so the change silently fails to land.
- Read as "finished with", a vanished branch sent `review-code` to the default branch. Squash and rebase merges rewrite the prerequisite's commits under fresh SHAs, so the SHAs this branch's history carries are nowhere in the default branch. `merge-base(<default>, HEAD)` therefore lands *below* the prerequisite and sweeps its commits into the reviewed range. Squash merge is the ordinary operation in this repository, so this is the common case rather than an edge one.

It needs no branch to exist: the lookup is by head branch *name*, which the PR record keeps after the branch is gone.

### Why the `MERGED` row's base is `refs/pull/<n>/head`

- **It bounds the range whatever the merge strategy was.** Taking the prerequisite's own head leaves the range holding exactly this task's commits, whether the prerequisite went in squashed, rebased, or as a merge commit. In the merge-commit case that point coincides with `merge-base(<default>, HEAD)`.
- **It is the one form that always resolves.** `refs/pull/<n>/head` outlives both the merge and the branch's deletion.

### Why the writer and the readers answer `MERGED` differently

`implement-work`'s **Base branch** rule sends a task whose prerequisite is already `MERGED` to the default branch and records no trailer at all, while the table above sends `MERGED` to the prerequisite's head. That is not a contradiction, because the two are reading different histories. A branch cut from the default branch *after* the merge has every one of its commits ahead of it. A branch cut while the prerequisite was still `OPEN` carries the prerequisite's commits inside its own history, and the prerequisite merging later does not remove them. Different history, different correct base — so the writer-side rule stands as it is.

## Why the lookups are tested the way they are

- **A PR's state is tested by `state`, and it has three values.** `OPEN`, `CLOSED` and `MERGED` are three cases, so "not merged" collapses the two that need opposite answers: a PR closed without merging is abandoned work, not work still in flight. This binds both sides of the mechanism — the writer reads `state` to choose what to branch from, and both readers read it to choose the base.
- **The stop rows stop rather than falling through to the default branch.** Falling through makes an unimplemented, abandoned, or ambiguous prerequisite indistinguishable from an independent task — and that surfaces only later, as a failure whose cause is nowhere in the diff. This table's stop rows, and the writer-side rule's own stop outcomes, both exist for that one reason.

## Absorbing the base at the completion gate

`implement-work`'s completion gate absorbs the base as a step of its own. Three things about that are worth the reasons, because each has an obvious alternative that is wrong.

- **Why at the gate, and not where the branch is cut.** Cutting from the base fixes a snapshot, and the branch then diverges from it for as long as the work takes. What has to be verified is the tree that will merge, so the absorb belongs at the point of verification — absorbed only at cut time, it is already stale by the first verify, and the gate then certifies a tree that is not the one going in.
- **Why merge, and not rebase.** Rebase rewrites commits that are already pushed, so it needs a force-push, which `ai/GUIDELINES.md` bans outright. A merge reaches the same state — the base is in — by adding a commit instead of rewriting any, so it needs no rewrite and no exception.
- **Why on any update, and not only on a conflict.** A conflict is only the part git can detect textually. Two changes that never touch the same lines can still be wrong together, and on the PR path nothing looks at that combination: the gate verified before the base moved, CI runs on the branch, and the review reads the diff. Absorbing whenever the base has moved is what makes the verified tree the merged tree; absorbing only on conflict leaves exactly the silent case unexamined.
