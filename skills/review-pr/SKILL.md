---
name: review-pr
description: Use to review a PR and return the findings to it as a PR review.
---

# Review PR

- Review a PR.
- Have every finding judged against the PR's own code.
- Return the result to the PR as one review in the form the user picks.
- Never change the PR's code.
- Never commit.
- Never push.
- Keep re-reviewing after the author pushes out of scope.
- Keep requesting changes out of scope.
- Keep replying to existing threads out of scope.
- Keep resolving existing threads out of scope.

## Orchestration model

- Dispatch no worker of its own here, since the reviewer and the verdict workers are `vet-code`'s.
- Invoke `propose-alternatives` before `vet-code` when the purpose is settled.

## Steps

### 1. Resolve the PR

- Take the PR number or URL from the caller.
- Ask when none is given.

1. Run the check-pr-repo script (`<skill-dir>/scripts/check-pr-repo.sh`) for the caller's PR reference. It answers `PR <n> repo=<owner>/<repo>` only when the repository the reference names is this checkout's `origin`. On `STOP <slug>`, report it and end the run.
2. Put the reviewer's 👀 reaction on the PR itself, in the repository item 1 answered. From here on, remove the reviewer's 👀 from it when the run ends, however it ends, whether or not this run put it there. If it cannot be removed, don't stop the run; the Report tells the user to remove it by hand.

### 2. Resolve the range, the purpose, and the requirements

- Run the shared resolve-range tool (`tools/resolve-range.sh`) for the PR number.
- On `NEED`, read the facts it names as `implement-work`'s `references/facts.md` defines them, add them to one facts file, and run the tool again with that file, for as long as it asks.
- On `RANGE <base>..<head>`, bind both SHAs.
- On `EMPTY`, report that there is nothing to review and end the run.
- On `STOP <slug>`, report it and end the run.
- Take the candidate for the PR's purpose from the issues it links and, for a sub-issue, its parent, since the purpose is the problem the PR should solve.
- Keep the PR body apart from the purpose, since the body is the author's claim and the means the author chose.
- Show the user the candidate and ask whether it is right, needs correcting, or is unknown.
- Ask with no candidate when there is no linked issue or the candidate only restates the PR body, since an issue's text alone does not settle the purpose.
- Ask in plain chat for facts outside this repository bearing on whether the means is sound when the purpose is settled, since callers in other repositories, an earlier reverted attempt, or another mechanism meeting the purpose would change the verdict.
- Go on without one when the user gives none, since the answer is optional.
- Take the settled purpose, what the linked issues state as requirements, and any facts the user gave as the requirements.
- Let the settled purpose win where it and an issue's requirements differ.
- Keep the PR body out of the requirements.
- Make no purpose-versus-means check when the purpose is unknown.
- Run the rest of the review as usual when the purpose is unknown.
- Take what the linked issues state, if any, as the requirements when the purpose is unknown.
- Skip `propose-alternatives` when the purpose is unknown: do not invoke it, chat the skip, and continue with no new prompt.
- Say so when no requirements result.
- Invoke `propose-alternatives` once with that settled purpose, the read-root below, and the current artifact when the purpose is settled.
- Take the PR's base at its current tip as the read-root, since it is the `pr.base.sha` fact fetched as a SHA, never the range's `<base>` merge-base, `<head>`, the head worktree Step 3 creates, or the session checkout.
- Leave comparison, the one review-findings pass, and the ask-person continue-vs-revisit to `propose-alternatives`'s own procedure.
- Continue on its return.
- Stop the review on revisit design and return to `plan-work`'s **Entry** with the finding, the branch name, and that branch's state.

### 3. Vet

- Check `<head>` out detached in a worktree placed per `superpowers:using-git-worktrees`'s directory convention and bind its absolute path as `<head-dir>`, since this checkout is not the PR's head and a worker reading files here judges code the PR does not contain.
- Remove the worktree when the run ends.
- Invoke `vet-code` once, handing it the committed range `<base>..<head>` with `<head-dir>` as the only place to read and search files at `<head>`, what the PR says it implements, and the requirements, saying so when they include a settled purpose, since a worker does not inherit this session's working directory.
- Take back its judged findings and re-judge none of them.

### 4. Draft

- Put each `needs-user` question to the user and ask which of those findings go into the PR.
- Write the review's summary and the `accept` findings as a JSON array of `{path, line, body}`, since `body` carries the severity and proposed fix, `path` is relative to the repository root never under `<head-dir>`, `line` is head-side, and either may be null.
- Include Minor and the user-included `needs-user` findings in the `accept` set.
- Ask the author in the summary what real problem the PR is meant to solve when the purpose is unknown.
- Run the build-review-payload script (`<skill-dir>/scripts/build-review-payload.sh`) for the range, the summary, and the findings.
- Show the user in chat the draft as it would be posted, with body and inline comments.
- Show each `reject` with its reason and each declined `needs-user` apart from the draft and never in it.

### 5. Choose

- Offer exactly three choices: **approve**, **comment only**, and **draft only**.
- Map **approve** to submit with APPROVE.
- Map **comment only** to submit with COMMENT.
- Map **draft only** to leaving a pending review unsubmitted.
- Never offer requesting changes.
- Recommend approve when no accepted finding is Critical or Important, no verdict is `needs-user`, and the purpose is known.
- Recommend comment only otherwise.

### 6. Post

- Run the post-review script (`<skill-dir>/scripts/post-review.sh`) for the choice the user made, with `APPROVE`, `COMMENT`, or `PENDING` for draft only.
- Write nothing else to the PR in this run but the 👀 of Step 1.
- Post nothing when the user chose none of the three.
- Report a `STOP <slug>` from this first call as nothing posted.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — create a pending review anchored to `<head>` by your own means in that repository.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — add each inline comment to it.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — submit it with that event unless the event is `PENDING`.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — put the payload's body on whichever of those steps the means lets set, and on the submit as well when the submit replaces it.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — end the write there and take no later step when a step fails.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — report that nothing was posted when the create itself fails.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — take no later step and report a possibly unconfirmed pending review when the create succeeded but no review id can be read, since the user must check it and submit or delete it.
- `WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<event>` — take the review's id right after the create as `implement-work`'s `references/facts.md` defines `review.id`, read the review back by it whether the write finished or stopped, and run the script again with the review id and the facts file for facts read afresh.
- `NEED <token>...` — read the facts it names as `implement-work`'s `references/facts.md` defines them, add them to one facts file, and run the script again with that file, for as long as it asks.
- `POSTED <state> <url>` — report the URL.
- `POSTED <state> <url>` — report the step that failed when one did.
- `STOP review-pending-left` — report that a pending review is still on the PR, not submitted, with the step that failed when one did, since its body may not be the draft's and the user must check the body then submit or delete it.
- Report any other `STOP <slug>` from the read-back with a review possibly on the PR in an unconfirmed state and a body not confirmed to be the draft's.

## Report

- Report the PR and the range reviewed and whether requirements were available.
- Report whether `propose-alternatives` was invoked or skipped and why.
- Report an empty finding or a finding when invoked.
- Report that the run waited on a finding.
- Report whether the purpose was checked against the means.
- Report that no check against outside facts was made when the purpose was settled but none were given.
- Report what was posted with its state and URL, or that nothing was posted, or that a pending review was left.
- Report the rejected findings with their reasons and the `needs-user` questions.
- Report that the 👀 is still on the PR and the user has to remove it by hand when it could not be removed.
