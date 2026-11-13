# Base resolution

## The prerequisite line

One line in the issue body, `Blocked-By: #N` alone on its line, `N` the prerequisite's issue number in the same repository. No line means the task stacks on nothing and its base is the default branch; one well-formed line means the base follows from the PR closing `#N` — its head while `OPEN`, the default branch once `MERGED`; two or more lines, or one that only looks like it (`Blocked-by #N`, `owner/repo#N`, a list marker in front), stops. A near-miss read as no line would cut the task from the default branch without its prerequisite's changes.

## Resolving the default branch

Never guess a branch name. Two rungs, in order — the remote's own HEAD, read live (`git ls-remote --symref`), then ask the user. `git symbolic-ref refs/remotes/origin/HEAD` is not a rung: a clone sets that symref once and never refreshes it, so after a default-branch rename it keeps naming the old one, and the base resolves to the wrong branch with nothing reporting the mistake.

## Reading the prerequisite back

Settle the base from the state of the PR closing `#N` — never from whether the branch still exists. The issue number is handed over only when the issue lives in origin's repository; any other issue, like no issue, answers the default branch, since a number names no repository and the line would be read from the same-numbered issue in origin.

| prerequisite PR state | `review-code`'s `<base>` | `pr-to-ready`'s retarget |
| --- | --- | --- |
| no issue of origin's repository | the default branch | none |
| no `Blocked-By:` line | the default branch | the default branch |
| `OPEN` | `git fetch origin <head>`, then `FETCH_HEAD` | back to `<head>` |
| `MERGED` | `git fetch origin refs/pull/<n>/head`, then `FETCH_HEAD` | the default branch, retargeting an existing PR that still points at `<head>` |
| anything else — ask a person | **stop** | **stop** |

`<n>` is the closing PR's number, printed beside the state.

A surviving branch may be long merged, so reading `OPEN` from the branch's existence hands `pr-to-ready` that branch as its base, and merging a PR into an already-merged branch puts nothing into the default branch. A vanished branch proves only that somebody tidied up, so reading "finished with" from its absence sends `review-code` to the default branch, where `merge-base(<default>, HEAD)` lands below the prerequisite and sweeps its commits into the reviewed range.

## Absorbing the base at the completion gate

- **Why at the gate, and not where the branch is cut.** Cutting from the base fixes a snapshot the branch then diverges from for as long as the work takes; what has to be verified is the tree that will merge, so the absorb belongs at the point of verification.
- **Why merge, and not rebase.** Rebase rewrites commits that are already pushed, so it needs a force-push, which is barred; a merge brings the base in by adding a commit instead of rewriting any.
- **Why on any update, and not only on a conflict.** A conflict is only the part git can detect textually — two changes that never touch the same lines can still be wrong together, and nothing else on the PR path examines that combination; absorbing whenever the base has moved is what makes the verified tree the merged tree.
