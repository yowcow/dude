---
name: address-review
description: Use to answer reviews, review threads, or comments on your own PR, named by their URLs.
---

# Address Review

- Answer the findings the caller names by URL on the viewer's own PR, once.
- End the run when `address-findings` returns.
- Keep findings no URL names out of scope.
- Keep requesting another review out of scope.

## Entry

- Take one or more URLs on one PR from the caller.
- Ask which PR to answer when the URLs name more than one.
- Read each URL by its fragment:
  - `#pullrequestreview-<id>`: that review's inline comments, and its body where the body makes a claim.
  - `#discussion_r<id>`: that one thread.
  - `#issuecomment-<id>`: that one comment.
- Ask which review, thread, or comment to answer when a URL carries no fragment.
- Confirm through `tools/origin-repo.sh` that origin names the PR's repository.
- Run the check-pr-author script (`tools/check-pr-author.sh`) for the PR number.
- On `NEED`, read the facts it names as `contracts/facts.md` defines them, add them to one facts file, and run it again with that file, for as long as it asks.
- Read `pr.state`, `pr.head.owner`, and `pr.head.ref` as `contracts/facts.md` defines them.
- Change nothing, report why, and end the run where origin is not the PR's repository, the answer is `OTHER` or `STOP <slug>`, `pr.state` is not `OPEN`, or `pr.head.owner` is not origin's owner.

## Range and workspace

- Run the shared resolve-range tool (`tools/resolve-range.sh`) for the PR number, handling `NEED` as above.
- On `RANGE <base>..<head>`, bind both SHAs.
- On `EMPTY` or `STOP <slug>`, report it and end the run.
- Run `tools/attach-workspace.sh` for `pr.head.ref` and a path placed per `superpowers:using-git-worktrees`'s directory convention.
- On `REUSE <path>` or `ATTACHED <path>`, take that path as the workspace.
- Change nothing, report why, and end the run on `CREATE`, or where the workspace's head is not `<head>` or `tools/check-clean.sh` run there reports it dirty.
  - Judging or fixing there answers code the PR does not hold.

## Judge

- Take each thread already resolved out of judging, and only report it.
- Take as the requirements the issues a closing keyword in the PR names.
- Keep the PR body out of the requirements.
- Invoke `judge-findings` with each finding as an item, a thread's replies beside it, against `<base>..<head>` with the workspace as the read-root and the requirements.
- Give it as the acceptance criteria: every `needs-user` names whom its question is for — the PR's author, for a decision the author owns, or the reviewer, where the finding's meaning cannot be taken.
- Re-judge no verdict, and route no `needs-user` by any judgment of this skill's own.
- Where a `needs-user` is on the measurement route, take that measurement once and bounded in the workspace, and invoke `judge-findings` again on that finding with the result.
- Ask the user a question for the author in chat, and take the answer as that finding's settlement.
- Settle a question for the reviewer as a question back, never fixing on a guess.
- Never fix a finding that invalidates the agreed design.
- Take it through `using-dude`'s **Escalation** instead: change nothing, and return to `plan-work`'s **Entry** with the finding, the part of the design it undoes, the branch name, and that branch's state.

## Address

- Invoke `address-findings` with each judged finding's settlement and place, the PR, and the workspace.
  - Give a review body or a comment no thread, with a link to its source.

## Report

- Report what `address-findings` returned, listing each unposted reply and each failed reply one by one.
- Report each resolved thread left unjudged.
- Report each review body taken as making no claim.
