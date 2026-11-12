---
name: review-pr
description: Use to review a PR and return the findings to it as a PR review.
---

# Review PR

- Review a PR.
- Have every finding judged against the PR's own code.
- Return the result to the PR as one review in the form the user picks, with replies and resolves on the viewer's earlier threads.
- Never change the PR's code.
- Never commit.
- Never push.
- Keep requesting changes out of scope.
- Keep replying to and resolving threads another login started out of scope.

## Orchestration model

- Dispatch no worker of its own here, since the reviewer and the verdict workers are `vet-code`'s and `judge-findings`'.
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
- Bind `<since>` as `<base>` when the caller asks for a review of the whole PR.
- Otherwise run the resolve-since script (`<skill-dir>/scripts/resolve-since.sh`) for the PR number and the range, handling `NEED` as above.
- On `WHOLE`, bind `<since>` as `<base>`.
- On `SINCE <sha>`, bind `<since>` as that SHA and tell the user in one line, without waiting for an answer, that this round reviews only the commits since the viewer's last review.
- On `UNCHANGED`, bind `<since>` as `<head>` and tell the user in one line, without waiting for an answer, that nothing was pushed since the viewer's last review and only the earlier findings are judged.
- On `STOP ask-since-rewritten` or `STOP ask-since-base-merged`, ask the user whether to review the whole PR or stop, binding `<since>` as `<base>` on whole and ending the run on stop.
  - A rewritten history leaves no range since the last review, and a merged base would put the base's own changes into it.
- On any other `STOP <slug>`, report it and end the run.
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
- Skip `propose-alternatives` when `<since>` is `<head>`: do not invoke it, chat the skip, and continue, since nothing was pushed since the viewer's last review.
- Say so when no requirements result.
- Invoke `propose-alternatives` once with the origin purpose its **Inputs** reaches from the issue behind the PR's closing keyword, or the settled purpose where there is none, the read-root below, and the current artifact when the purpose is settled.
- Take as the read-root the SHA `tools/fetch-to-sha.sh` prints for the `pr.base.ref` fact, never `pr.base.sha`, the range's `<base>` merge-base, `<head>`, the head worktree Step 3 creates, or the session checkout, since `pr.base.sha` may lag the base's tip.
- Leave comparison, the one review-findings pass, and the ask-person continue-vs-revisit to `propose-alternatives`'s own procedure.
- Continue on its return.
- Stop the review on revisit design and return to `plan-work`'s **Entry** with the finding, the branch name, and that branch's state.

### 3. Vet

- Check `<head>` out detached in a worktree placed per `superpowers:using-git-worktrees`'s directory convention and bind its absolute path as `<head-dir>`, since this checkout is not the PR's head and a worker reading files here judges code the PR does not contain.
- Remove the worktree when the run ends.
- Take as the earlier findings every unresolved thread on the PR whose first comment is the viewer's, from any review but a pending one, taking the viewer as `implement-work`'s `references/facts.md` defines `viewer.login`.
- Invoke `judge-findings` with each earlier finding as an item — its text, severity, and location as posted with the commit it was posted on, with the replies in its thread beside it — against `<base>..<head>` with `<head-dir>` as the read-root and the requirements.
- Give it as the acceptance criteria: accept a finding that still stands at `<head>`; reject one that does not, the reason saying whether it was resolved or was not valid.
- Read `accept` as still standing and `reject` as resolved or not valid, as its reason says.
- Put each `needs-user` question to the user before invoking `vet-code`, and take the answer as one of those three.
- Skip `vet-code` when `<since>` is `<head>`, since there is no new commit to review.
- Invoke `vet-code` once, handing it the committed range `<since>..<head>` with `<head-dir>` as the only place to read and search files at `<head>`, what the PR says it implements, and the requirements, saying so when they include a settled purpose, and the earlier rounds' record below, since a worker does not inherit this session's working directory.
- Hand that record a resolved earlier finding as accepted and fixed, a not-valid one as rejected with its reason, and a still-standing one as accepted and not yet fixed.
  - Never hand a resolved one as rejected, since the record then stops the same problem from being raised when it comes back.
- Take back its judged findings and re-judge none of them.

### 4. Draft

- Put each `needs-user` question to the user and ask which of those findings go into the PR.
- Keep out of the findings any finding with the same claim about the same code as an earlier finding, wherever that code now sits, whatever that finding's judgment, and answer it only in that earlier finding's reply, since otherwise every run opens another thread for one finding.
- Turn a resolved or not-valid earlier finding to still standing when such a finding is `accept` or a user-included `needs-user`.
- Draft a reply to each earlier finding giving its judgment, marking resolved and not-valid ones for resolving and leaving still-standing ones open.
- Write the review's summary and the `accept` findings as a JSON array of `{path, line, body}`, since `body` carries the severity and proposed fix, `path` is relative to the repository root never under `<head-dir>`, `line` is head-side, and either may be null.
- Include Minor and the user-included `needs-user` findings in the `accept` set.
- Ask the author in the summary what real problem the PR is meant to solve when the purpose is unknown.
- Say in the summary, when `<since>` is not `<base>`, that the findings in the viewer's earlier review bodies were not re-checked.
- Run the build-review-payload tool (`tools/build-review-payload.sh`) for `<base>..<head>`, never `<since>..<head>`, the summary, and the findings, since the PR's own diff decides which lines take an inline comment.
- Show the user in chat the draft as it would be posted, with body, inline comments, and each reply with whether its thread is resolved.
- Show each `reject` with its reason and each declined `needs-user` apart from the draft and never in it.

### 5. Choose

- Offer exactly three choices: **approve**, **comment only**, and **draft only**.
- Map **approve** to submit with APPROVE.
- Map **comment only** to submit with COMMENT.
- Map **draft only** to leaving a pending review unsubmitted.
- Never offer requesting changes.
- Recommend approve when no accepted finding and no still-standing earlier finding, at the higher of its original severity and a same finding's this round that is `accept` or a user-included `needs-user`, is Critical or Important, no verdict of `vet-code`'s is `needs-user`, and the purpose is known.
- Recommend comment only otherwise.

### 6. Post

- Run the post-review tool (`tools/post-review.sh`) for the choice the user made, with `APPROVE`, `COMMENT`, or `PENDING` for draft only.
- Write nothing else to the PR in this run but the 👀 of Step 1 and the replies and resolves below.
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
- `POSTED APPROVED` or `POSTED COMMENTED` — then post each drafted reply to its thread and resolve the threads marked for it, by your own means; post none on any other answer.
- Stop at the first reply or resolve that fails and take no later one.
- `STOP review-pending-left` — report that a pending review is still on the PR, not submitted, with the step that failed when one did, since its body may not be the draft's.
- `STOP review-pending-left` — have the user check the body and submit or delete it, since its body may not be the draft's.
- Report any other `STOP <slug>` from the read-back with a review possibly on the PR in an unconfirmed state and a body not confirmed to be the draft's.

## Report

- Report the PR, the range handed to `vet-code` (`<since>..<head>`) or that `vet-code` was skipped because nothing was pushed since the viewer's last review, and whether requirements were available.
- Report, when `<since>` is not `<base>`, that the findings in the viewer's earlier review bodies were not re-checked.
- Report whether `propose-alternatives` was invoked or skipped and why.
- Report an empty finding or a finding when invoked.
- Report that the run waited when invoked with a finding.
- Report whether the purpose was checked against the means.
- Report that no check against outside facts was made when the purpose was settled but none were given.
- Report what was posted with its state and URL, or that nothing was posted, or that a pending review was left.
- Report the rejected findings with their reasons and the `needs-user` questions.
- Report that the 👀 is still on the PR and the user has to remove it by hand when it could not be removed.
- Report which of the viewer's reviews of this PR this one is, counting the viewer's submitted reviews with a body from before this run and then this one.
- Report each earlier finding with its judgment.
- Report the replies and resolves written and each drafted one not written, including all of them when no review was posted or draft only was chosen.
