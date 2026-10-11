---
name: review-pr
description: Use to review a PR someone else opened and return the findings to it as a PR review.
---

# Review PR

Review a PR somebody else opened, have every finding judged against the PR's own code, and return the result to the PR as one review, in the form the user picks.

- This skill never changes the PR's code, never commits, and never pushes. A PR you authored belongs to `pr-to-ready`.
- Re-reviewing after the author pushes, requesting changes, and replying to or resolving existing threads are not part of it.

## Orchestration model

**This skill dispatches no worker of its own: the reviewer and the verdict workers are `vet-code`'s.** The orchestrator resolves the PR, calls `vet-code` once, drafts the review, and makes the one write to the PR the user chose.

## Steps

### 1. Resolve the PR

Take the PR number or URL from the caller; if none was given, ask.

1. Run `<skill-dir>/scripts/check-pr-repo.sh <pr-ref>`. It answers `PR <n> repo=<owner>/<repo>` only when the repository the reference names is both this checkout's `origin` and the repository `gh` resolves here. On `STOP <slug>`, report it and end the run.
2. Run `<skill-dir>/scripts/check-pr-author.sh <n>`. On `SELF`, stop and point the user to `pr-to-ready`. On `OTHER`, go on. On `STOP <slug>`, report it and end the run.

### 2. Resolve the range and the requirements

- Run `<skill-dir>/../review-code/scripts/resolve-range.sh <n>`. On `RANGE <base>..<head>`, bind both SHAs. On `EMPTY`, report that there is nothing to review and end the run. On `STOP <slug>`, report it and end the run.
- The requirements are the PR's body and the issues it links. Where neither states any, say so.

### 3. Vet

- Check `<head>` out detached in a worktree placed per `superpowers:using-git-worktrees`'s directory convention, and bind its absolute path as `<head-dir>`: this checkout is not the PR's head, and a worker reading files here judges code the PR does not contain. Remove the worktree when the run ends.
- Invoke `vet-code` once, handing it as the scope the committed range `<base>..<head>` together with `<head-dir>` as the only place to read and search files at `<head>`, what the PR says it implements, and the requirements. A worker does not inherit this session's working directory, and the scope is the one input `vet-code` passes to its reviewer and its verdict workers alike. Take back its judged findings and re-judge none of them.

### 4. Draft

- Write the review's summary, and one entry per `accept` finding — Minor included — whose text carries its severity and proposed fix, with its path and head-side line where it has them.
- Run `<skill-dir>/scripts/build-review-payload.sh <base> <head> <summary-file> <findings-file>`. It makes a finding an inline comment only on a line the diff adds, and puts every other finding into the review body.
- Show the user in chat the draft as it would be posted — body and inline comments — and, apart from it and never in it, each `reject` with its reason and each `needs-user` with its question.

### 5. Choose

Offer exactly three choices: **approve** (submit with APPROVE), **comment only** (submit with COMMENT), and **draft only** (leave a pending review, unsubmitted). Never offer requesting changes.

Recommend approve when no accepted finding is Critical or Important and no verdict is `needs-user`; otherwise recommend comment only.

### 6. Post

Run `<skill-dir>/scripts/post-review.sh <owner> <repo> <n> <head> <event> <payload-file>` once, for the choice the user made: `APPROVE`, `COMMENT`, or `PENDING` for draft only. Nothing else in this run writes to the PR. When the user chose none of the three, post nothing.

- `POSTED <state> <url>` — report the URL.
- `STOP <slug>` — report it; nothing was posted.

## Report

- the PR and the range reviewed, and whether requirements were available
- what was posted — its state and URL — or that nothing was
- the rejected findings with their reasons, and the `needs-user` questions
