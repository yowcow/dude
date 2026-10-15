---
name: review-pr
description: Use to review a PR someone else opened and return the findings to it as a PR review.
---

# Review PR

Review a PR somebody else opened, have every finding judged against the PR's own code, and return the result to the PR as one review, in the form the user picks.

- This skill never changes the PR's code, never commits, and never pushes.
- Re-reviewing after the author pushes, requesting changes, and replying to or resolving existing threads are not part of it.

## Orchestration model

**This skill dispatches no worker of its own: the reviewer and the verdict workers are `vet-code`'s.** The orchestrator resolves the PR, calls `vet-code` once, drafts the review, makes the one review write to the PR the user chose, and puts the reviewer's 👀 on the PR while the review runs, removing it when the run ends.

## Steps

### 1. Resolve the PR

Take the PR number or URL from the caller; if none was given, ask.

1. Run `<skill-dir>/scripts/check-pr-repo.sh <pr-ref>`. It answers `PR <n> repo=<owner>/<repo>` only when the repository the reference names is this checkout's `origin`. On `STOP <slug>`, report it and end the run.
2. Run `tools/check-pr-author.sh <n>`. On `NEED`, read the facts it names as `implement-work`'s `references/facts.md` defines them, write them to a file, and run it again with `--facts <file>` added. On `SELF`, stop and report it. On `OTHER`, go on. On `STOP <slug>`, report it and end the run.
3. Put the reviewer's 👀 reaction on the PR itself, in the repository item 1 answered. From here on, remove the reviewer's 👀 from it when the run ends, however it ends, whether or not this run put it there. If it can't be removed, don't stop the run; the Report tells the user to remove it by hand.

### 2. Resolve the range, the purpose, and the requirements

- Run `tools/resolve-range.sh <n>`. On `NEED`, read the facts it names as `implement-work`'s `references/facts.md` defines them, add them to one facts file, and run it again with `--facts <file>` added, for as long as it asks. On `RANGE <base>..<head>`, bind both SHAs. On `EMPTY`, report that there is nothing to review and end the run. On `STOP <slug>`, report it and end the run.
- Take a candidate for the PR's purpose, the problem it should solve, from the issues it links and, for a sub-issue, its parent. The PR body is the author's claim, the means the author chose, and stays apart from the purpose.
- Show the user the candidate and ask whether it is right, needs correcting, or is unknown. Ask with no candidate when there is no linked issue or the candidate only restates the PR body: an issue's text alone does not settle the purpose.
- **Purpose settled** (confirmed or corrected): ask for facts outside this repository that bear on whether the means is sound — callers in other repositories, an earlier attempt at the same approach that was reverted, another mechanism that already meets the purpose; the answer is optional, and the run goes on without one. The requirements are the settled purpose, what the linked issues state as requirements, and any facts the user gave; where the purpose and an issue's requirements differ, the settled purpose wins. The PR body is not a requirement.
- **Purpose unknown**: make no purpose-versus-means check and run the rest of the review as usual. The requirements are what the linked issues state, if any.
- Where no requirements result, say so.

### 3. Vet

- Check `<head>` out detached in a worktree placed per `superpowers:using-git-worktrees`'s directory convention, and bind its absolute path as `<head-dir>`: this checkout is not the PR's head, and a worker reading files here judges code the PR does not contain. Remove the worktree when the run ends.
- Invoke `vet-code` once, handing it as the scope the committed range `<base>..<head>` together with `<head-dir>` as the only place to read and search files at `<head>`, what the PR says it implements — the PR body —, and the requirements, saying so when they include a settled purpose. A worker does not inherit this session's working directory, and the scope is the one input `vet-code` passes to its reviewer and its verdict workers alike. Take back its judged findings and re-judge none of them.

### 4. Draft

- Put each `needs-user` question to the user and ask which of those findings go into the PR.
- Write the review's summary, and the `accept` findings — Minor included, and the `needs-user` findings the user included — as a JSON array of `{path, line, body}`: `body` carries the severity and proposed fix, `path` is relative to the repository root — never under `<head-dir>` — and `line` is head-side; either may be null. When the purpose is unknown, the summary asks the author what real problem the PR is meant to solve.
- Run `<skill-dir>/scripts/build-review-payload.sh <base> <head> <summary-file> <findings-file>`. It makes a finding an inline comment only on a line the diff adds, and puts every other finding into the review body.
- Show the user in chat the draft as it would be posted — body and inline comments — and, apart from it and never in it, each `reject` with its reason and each `needs-user` the user declined.

### 5. Choose

Offer exactly three choices: **approve** (submit with APPROVE), **comment only** (submit with COMMENT), and **draft only** (leave a pending review, unsubmitted). Never offer requesting changes.

Recommend approve when no accepted finding is Critical or Important and no verdict is `needs-user`, and the purpose is known; otherwise recommend comment only.

### 6. Post

Run `<skill-dir>/scripts/post-review.sh <n> <head> <event> <payload-file>` for the choice the user made: `APPROVE`, `COMMENT`, or `PENDING` for draft only. Nothing else in this run writes to the PR but the 👀 of Step 1. When the user chose none of the three, post nothing. A `STOP <slug>` from this first call means nothing was posted: report it.

- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event> comments=<k>` — write the review in that repository by your own means, in steps: create a pending review anchored to `<head>`, add each inline comment to it, and, unless the event is `PENDING`, submit it with that event; the payload's body goes on whichever of those steps your means lets set it, and on the submit as well when the submit replaces it. A step that fails ends the write there: take no later step. When the create itself fails, report that nothing was posted. When the create succeeded but no review id can be read, take no later step, and report that a pending review may be on the PR, not confirmed, and that the user must check it and submit or delete it. Otherwise take the review's id as `implement-work`'s `references/facts.md` defines `review.id`, right after the create, and read the review back by it whether the write finished or stopped, and run the script again with `--posted <review-id>` and `--facts <file>` for facts read afresh.
- `NEED <token>...` — read the facts it names as `implement-work`'s `references/facts.md` defines them, add them to one facts file, and run it again with `--facts <file>` added, for as long as it asks.
- `POSTED <state> <url>` — report the URL, and the step that failed when one did.
- `STOP review-pending-left` — report that a pending review is still on the PR, not submitted, with the step that failed when one did, that its body may not be the draft's, and that the user must check the body, then submit or delete it.
- any other `STOP <slug>` from the read-back — report it and that a review may be on the PR in a state not confirmed, with a body not confirmed to be the draft's.

## Report

- the PR and the range reviewed, and whether requirements were available
- whether the purpose was checked against the means, and when it was settled but no facts outside the repository were given, that no check against such facts was made
- what was posted — its state and URL — or that nothing was, or that a pending review was left
- the rejected findings with their reasons, and the `needs-user` questions
- when the 👀 could not be removed, that it is still on the PR and the user has to remove it by hand
