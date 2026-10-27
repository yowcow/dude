# Base-Branch trailer

The contract and the reasons; the commands a skill actually runs belong in that skill's `scripts/` and the shared `tools/`.

## The contract

One `Base-Branch: <base>` line in the trailer block of the task's **first** commit. `<base>` is the bare branch name — no `origin/` prefix, no `refs/heads/` path. Branching from the default branch records nothing.

## The prerequisite line

One line in the issue body, `Blocked-By: #N` alone on its line, `N` the prerequisite's issue number in the same repository. No line means the task stacks on nothing and its base is the default branch; one well-formed line means the base follows from the PR closing `#N` — its head while `OPEN`, the default branch once `MERGED`; two or more lines, or one that only looks like it (`Blocked-by #N`, `owner/repo#N`, a list marker in front), stops. A near-miss read as no line would cut the task from the default branch without its prerequisite's changes.

## Resolving the default branch

Never guess a branch name. Two rungs, in order — the remote's own HEAD, read live (`git ls-remote --symref`), then ask the user. `git symbolic-ref refs/remotes/origin/HEAD` is not a rung: a clone sets that symref once and never refreshes it, so after a default-branch rename it keeps naming the old one, and the base resolves to the wrong branch with nothing reporting the mistake.

## Reading the trailer back

Where a stack runs deeper than one, the nearest trailer wins. Look the prerequisite's PR up by its head branch name, and settle the base from its state — never from whether the branch still exists.

| trailer / prerequisite PR state | `review-code`'s `<base>` | `pr-to-ready`'s `--base` |
| --- | --- | --- |
| no trailer | the default branch | omit |
| `OPEN` | `git fetch origin <recorded>`, then `FETCH_HEAD` | `<recorded>` |
| `MERGED` | `git fetch origin refs/pull/<n>/head`, then `FETCH_HEAD` | the default branch — omit `--base`, and retarget an existing PR that still points at `<recorded>` |
| anything else — ask a person | **stop** | **stop** |

`<n>` is the PR number the lookup printed beside the state. The no-trailer row needs no lookup.

A surviving branch may be long merged, so reading `OPEN` from the branch's existence hands `pr-to-ready` that branch as `--base`, and merging a PR into an already-merged branch puts nothing into the default branch. A vanished branch proves only that somebody tidied up, so reading "finished with" from its absence sends `review-code` to the default branch, where `merge-base(<default>, HEAD)` lands below the prerequisite and sweeps its commits into the reviewed range.

## Absorbing the base at the completion gate

- **Why at the gate, and not where the branch is cut.** Cutting from the base fixes a snapshot the branch then diverges from for as long as the work takes; what has to be verified is the tree that will merge, so the absorb belongs at the point of verification.
- **Why merge, and not rebase.** Rebase rewrites commits that are already pushed, so it needs a force-push, which is barred; a merge brings the base in by adding a commit instead of rewriting any.
- **Why on any update, and not only on a conflict.** A conflict is only the part git can detect textually — two changes that never touch the same lines can still be wrong together, and nothing else on the PR path examines that combination; absorbing whenever the base has moved is what makes the verified tree the merged tree.
