---
name: vet-code
description: Use as a component when another skill needs one round of code review findings, each already judged.
---

# Vet Code

Resolving the scope, applying or verifying a fix, deciding whether another round runs, and posting anything anywhere are the caller's. This skill touches neither the code nor GitHub.

## Orchestration model

**This skill dispatches two kinds of worker: a read-only reviewer, and one verdict worker per finding.** Nothing else leaves the main loop.

- The reviewer is a read-only worker, dispatched through `superpowers:requesting-code-review` with the prompt **Reviewer prompt** defines. It returns that template's output. It never edits code, never runs the project's checks, and never commits.
- The reviewer goes out at the `high` tier in `using-dude`'s **Worker tier**: a finding it doesn't return comes back as "nothing found", and the caller reads that as clean.
- One reviewer per invocation, fresh each time — the fan-out here is fixed at one, because a diff doesn't warrant more.
- **Judging a finding never happens in the main loop**, and goes out at that same `high` tier.
  - The main loop may have written this code or fixed it, so a verdict reached there rests on its own account of why the code reads this way, and a real finding rejected on that account is rejected for good — no later round reads it again.
  - One worker per finding, launched together, each applying `superpowers:receiving-code-review` to its one finding and returning `accept` with the fix, `reject` with the technical reason, or `needs-user`.
  - Each gets the finding, the scope and requirements the reviewer got, and the earlier rounds' record **Reviewer prompt** already defines; the main loop's own history is what it does not get.
- What a read-only worker buys is a fresh context: it reads the code without having written it, so it is not anchored on why the code ended up this way.

## Reviewer prompt

`superpowers:requesting-code-review` is the dispatch mechanism. The prompt body is that procedure's template. The prompt is complete only when What to Check, Calibration, and Output Format are verbatim except placeholder fill. The caller's four inputs fill placeholders and may append after the template; they are not an alternate completeness test.

The caller hands the scope in one of these four shapes:

- **a committed range** — the two SHAs bounding it. Fill `BASE_SHA` and `HEAD_SHA` only, including those same SHAs wherever the template Git Range to Review section repeats them.
- **uncommitted changes** — where they are: staged, unstaged, and untracked alike. Do not send the reviewer to a worktree of its own here — a worktree holds a revision, and these changes are in none. That outranks the template Read-Only Review worktree line.
- **paths with no range** — the paths themselves, and that the review covers their current state on this checkout rather than a diff. Return the same caveat with the findings: nothing constrains the review to recent change, so the findings may be about code this work never touched.
- **a PR** — the range the caller resolved for it, handed over as a committed range. Reviewing that diff locally is this skill's job.

For uncommitted changes or paths with no range, replacing the Git Range to Review section as a whole (its two diff command lines included) with that shape's description is the fill. Do not invent SHAs. This is not a rewrite of What to Check, Calibration, or Output Format.

When the caller's scope includes a read-root — a directory already bound as the only place to read the head — pass it beside the filled SHAs. For that dispatch it outranks the template's this-checkout and any instruction that the reviewer create its own worktree. SHA fill is not the whole scope.

**What was implemented** fills `DESCRIPTION` — what the change does, or for a paths-only scope what the code is for.

**The requirements** fill `PLAN_OR_REQUIREMENTS` — the plan, or the original request. When there is none, say so in that placeholder: the review then runs against the repository's own standards and the code's evident intent. Return that with the findings too, so a reader of the caller's report knows plan alignment was not checked.

After the template, append only these viewpoint extras:

- **Optionally, that the requirements include a settled purpose** — the problem the change exists to solve. Only when the caller says so, tell the reviewer to compare the means with that purpose and to name what the means gives up where a way to keep it exists, such as looser coupling or less room for defects. A loss of that kind is rated by what it costs, not Minor because the code works.
- **The earlier rounds** — from the caller's second round on, findings accepted and fixed, and findings rejected with the reason. A reviewer not shown the rejections re-litigates them.

Also after the template: Confine every search to the project root or narrower.

## Output

Receive the template output as-is. Hand verdict workers Issues only (Critical / Important / Minor). Strengths, Recommendations, and Assessment are not findings. Assessment Ready to merge is not this skill declaring the code clean; clean remains the caller's, from whether blocking findings exist.

For each finding: the finding as the reviewer stated it, its severity — Critical, Important, or Minor — its location, and its verdict.

- A worker verifies the claim against the code before accepting it, and rejects — with a stated reason — a finding that is wrong, that only reflects reviewer preference, or that asks for work beyond the request.
- Where the call is a person's rather than a technical one, it returns `needs-user`, with the question to put to that person and why the decision is theirs.

Alongside the findings, return whichever caveat **Reviewer prompt** asks for: a paths-only scope, or no requirements.
