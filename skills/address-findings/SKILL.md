---
name: address-findings
description: Use as a component when another skill needs judged review findings on a PR fixed, verified, and answered.
---

# Address Findings

- Leave collecting the findings to the caller.
- Leave judging them to the caller.
- Leave deciding whether another round or review runs to the caller.
  - Send the fixed diff to no review here.
- Leave asking a person to the caller.

## Inputs

- Per finding, its settlement: fix (an `accept` with its fix), no fix (the reason), or a question back (the question).
- Per finding, its place: a thread, or none.
  - A finding with no thread comes with a link to its source.
- The PR, and a workspace attached to its head.
- A lead text for the head of the comment, only where the caller needs one.
- The unposted replies a previous invocation returned, only where the caller carries them over.

## Fix

- Apply each accepted fix in the workspace, run the relevant tests and lint, commit, and push.
- Then confirm CI passed on the pushed head.
- With nothing to fix, push nothing.
- Fix never again what a carried-over reply says was fixed.
- Before posting such a reply, confirm CI passed on the PR's head, counting its push as rejected where that head lacks its commit.
- With nothing to fix and no carried-over "fixed" reply, wait for no CI.
- Where the push is rejected, CI fails, or the bounded wait runs out, post nothing and return every unposted reply to the caller.

## Replies

- Immediately before the first reply or comment, check whether the viewer, `viewer.login` as `implement-work`'s `references/facts.md` defines it, holds a pending review on the PR.
- Where it does, post nothing and return every unposted reply, since a reply joins that draft.
  - Never add to, submit, or delete that review.
- Reply to a finding with a thread in that thread.
- Resolve the thread once its reply is posted.
- Never resolve a thread that got a question back.
- Gather the findings with no thread into one comment per invocation.
- Open that comment with the SHA of the commit the findings were judged at: the workspace's head when this skill was invoked, before its own fixes.
- Follow it with the caller's lead text, where given.
- Follow that with each finding under its own heading, with a link to its source.
- Paraphrase each finding's substance there, never quoting it verbatim.
- Put no mentions in that comment.
- Post that comment only where at least one finding has no thread or the caller passed a lead text.
- Make each reply one of: what was fixed and its commit, why it is not fixed, or the question.
- Post a no-fix reply without asking for approval first.

## Output

- Return the replies posted.
- Return the replies that failed.
- Return the unposted replies, each with its reason: the push was rejected, CI failed, the CI wait timed out, or a pending review.
