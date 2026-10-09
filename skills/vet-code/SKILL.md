---
name: vet-code
description: Use as a component when another skill needs one round of code review findings, each already judged.
---

# Vet Code

Resolving the scope, applying or verifying a fix, deciding whether another round runs, and posting anything anywhere are the caller's. This skill touches neither the code nor GitHub.

## Orchestration model

**This skill dispatches two kinds of worker: a read-only reviewer, and one verdict worker per finding.** Nothing else leaves the main loop.

- The reviewer is a read-only worker, dispatched through `superpowers:requesting-code-review` with the prompt **Reviewer prompt** defines. It returns findings only. It never edits code, never runs the project's checks, never commits, and never declares the code clean.
- The reviewer goes out at the tier `using-dude`'s **Worker tier** sets for a marked worker: a finding it doesn't return comes back as "nothing found", and the caller reads that as clean.
- One reviewer per invocation, fresh each time — the fan-out here is fixed at one, because a diff doesn't warrant more.
- **Judging a finding never happens in the main loop**, and goes out at that same marked tier.
  - The main loop may have written this code or fixed it, so a verdict reached there rests on its own account of why the code reads this way, and a real finding rejected on that account is rejected for good — no later round reads it again.
  - One worker per finding, launched together, each applying `superpowers:receiving-code-review` to its one finding and returning `accept` with the fix, `reject` with the technical reason, or `needs-user`.
  - Each gets the finding, the scope and requirements the reviewer got, and the earlier rounds' record **Reviewer prompt** already defines; the main loop's own history is what it does not get.
  - The caller applies the accepted fixes and verifies them against the project's checks, and re-judges no verdict.
- What a read-only worker buys is a fresh context: it reads the code without having written it, so it is not anchored on why the code ended up this way.

## Reviewer prompt

`superpowers:requesting-code-review` is the dispatch mechanism; what the reviewer is told is this skill's own. Whatever shape that dispatch offers to carry it, the prompt is complete when it holds these four, all from the caller:

1. **The scope** — as the caller resolved it, in one of these four shapes:
   - **a committed range** — the two SHAs bounding it;
   - **uncommitted changes** — where they are: staged, unstaged, and untracked alike. Don't send the reviewer to a worktree of its own here — a worktree holds a revision, and these changes are in none;
   - **paths with no range** — the paths themselves, and that the review covers their current state on this checkout rather than a diff. Return the same caveat with the findings: nothing constrains the review to recent change, so the findings may be about code this work never touched;
   - **a PR** — the range the caller resolved for it, handed over as a committed range. Reviewing that diff locally is this skill's job; posting anything to the PR is not.
2. **What was implemented** — what the change does, or for a paths-only scope what the code is for.
3. **The requirements** — the plan, or the original request. When there is none, say so in the prompt: the review then runs against the repository's own standards and the code's evident intent. Return that with the findings too, so a reader of the caller's report knows plan alignment was not checked.
4. **The earlier rounds** — from the caller's second round on, findings accepted and fixed, and findings rejected with the reason. A reviewer not shown the rejections re-litigates them.

Confine every search to the project root or narrower.

## Output

For each finding: the finding as the reviewer stated it, its severity — Critical, Important, or Minor — its location, and its verdict.

- A worker verifies the claim against the code before accepting it, and rejects — with a stated reason — a finding that is wrong, that only reflects reviewer preference, or that asks for work beyond the request.
- Where the call is a person's rather than a technical one, it returns `needs-user`, with the question to put to that person and why the decision is theirs.

Alongside the findings, return whichever caveat **Reviewer prompt** asks for: a paths-only scope, or no requirements.
