---
name: vet-code
description: Use as a component when another skill needs one round of code review findings, each already judged.
---

# Vet Code

Resolving the scope, applying or verifying a fix, deciding whether another round runs, and posting anything anywhere are the caller's. This skill touches neither the code nor GitHub.

## Orchestration model

**This skill dispatches one read-only reviewer; judging goes to `judge-findings`.** Nothing else leaves the main loop.

- The reviewer is a read-only worker, dispatched through `superpowers:requesting-code-review` with the prompt **Reviewer prompt** defines. It returns that template's output. It never edits code, never runs the project's checks, and never commits.
- The reviewer goes out at the `high` tier in `using-dude`'s **Worker tier**: a finding it doesn't return comes back as "nothing found", and the caller reads that as clean.
- One reviewer per invocation, fresh each time — the fan-out here is fixed at one, because a diff doesn't warrant more.
- Once the reviewer returns, hand `judge-findings` every Issues finding, and every Declined to judge line as a candidate, with the scope and requirements the reviewer got, and the earlier rounds' record. Every Declined line is handed over however the earlier rounds' record holds it, and that record travels as context, never as a filter; a line dropped as already judged never reaches the judge. As the acceptance criteria, hand it the template's "The spec is a vision document" paragraph verbatim, plus: a candidate sitting outside the plan or spec is why the reviewer set it aside, not a ground to reject it, and neither is the code being unchanged since the previous round when the candidate claims something about that code. A line that only discloses part of the scope went unreviewed is not such a candidate.
- What a read-only worker buys is a fresh context: it reads the code without having written it, so it is not anchored on why the code ended up this way.

## Reviewer prompt

`superpowers:requesting-code-review` is the dispatch mechanism. The prompt is that procedure's template verbatim with its four placeholders filled: nothing in the template body is replaced, dropped, or appended after. What the reviewer needs beyond the template travels inside `PLAN_OR_REQUIREMENTS`, since a placeholder's content is the caller's to write.

The caller hands the scope in one of these four shapes:

- **a committed range** — the two SHAs bounding it. Fill `BASE_SHA` and `HEAD_SHA` with them.
- **uncommitted changes** — where they are: staged, unstaged, and untracked alike.
- **paths with no range** — the paths themselves, and that the review covers their current state on this checkout rather than a diff. Return the same caveat with the findings: nothing constrains the review to recent change, so the findings may be about code this work never touched.
- **a PR** — the range the caller resolved for it, handed over as a committed range. Reviewing that diff locally is this skill's job.

Do not invent SHAs: where the scope has none, fill both `BASE_SHA` and `HEAD_SHA` with `N/A`.

**What was implemented** fills `DESCRIPTION` — what the change does, or for a paths-only scope what the code is for.

**The requirements** fill `PLAN_OR_REQUIREMENTS` — the entry artifact where the caller has one, with the plan's location beside it where one exists, and otherwise the original request; when there is none, say so there, so the review runs against the repository's own standards and the code's evident intent, and return that with the findings too, so a reader of the caller's report knows plan alignment was not checked. After that, in the same placeholder, write these as plain instructions, each only when it applies:

- **Range shape** — for uncommitted changes or paths with no range: the scope as its shape above describes it, and that the Git Range to Review section does not apply and is to be ignored, its diff commands included.
- **Worktree** — for uncommitted changes: review this checkout's current dirty state, and do not create a worktree, since a worktree holds a revision and these changes are in none. For paths with no range: review this checkout's current state; do not create a worktree.
- **Read-root** — when the caller's scope includes one, a directory already bound as the only place to read and search the head: for this dispatch it outranks the template's this-checkout, any instruction to create a worktree, and the project-root search confine; every search is confined to that directory.
- **Ledger rows** — when the caller hands any over: answer each row against the code as it now stands, keeping the row with its answer — the finding it is and its severity, or that it no longer stands and why, and never as a `Declined to judge` line. They narrow nothing: the scope shape is the caller's, and every search still covers the whole scope at every severity, as it would without them.
- **Purpose** — only when the caller says the requirements include a settled purpose, the problem the change exists to solve: compare the means with that purpose and name what the means gives up where a way to keep it exists, such as looser coupling or less room for defects. A loss of that kind is rated by what it costs, not Minor because the code works.
- **Earlier rounds** — from the caller's second round on, findings accepted and fixed, and findings or Declined to judge lines rejected with the reason. The record does not narrow the review: cover the whole scope at every severity, places unchanged since the previous round included; the record stops only a finding it holds as rejected from being raised again, and a finding accepted and fixed that still stands is raised again. A reviewer not shown the rejections re-litigates them.
- **Confine** — every search stays at the project root or narrower.
- **Tests** — answer "All tests passing?" from the diff alone: run neither the project's checks nor any code from the range under review, and say the checks were not run.

Close with one sentence: where these instructions and the template disagree, these win.

## Output

Receive the template output as-is. Strengths, Recommendations, and Assessment are not findings. Assessment Ready to merge is not this skill declaring the code clean; clean remains the caller's, from whether blocking findings exist.

For each finding: the finding as the reviewer stated it, its severity — Critical, Important, or Minor — its location, and its verdict: an `accept` with its fix, a `reject` with its reason, or `needs-user` with its question — none of them reworded, and no value beside them; for each Declined to judge line, the line as the reviewer stated it, its verdict in the same three tokens, and whether it stayed declined or became a finding, with a line that became a finding staying in the finding list too, for its severity and verdict.

For each ledger row the caller handed over — only lines carrying the execution method's `Ruling:` marker, and deferred-minor lines where the caller kept them: the finding it became, returned in the finding list with the row it came from kept, or one line `Ledger row closed: <row> — <why it no longer stands>`. A row whose finding the earlier rounds' record already holds as rejected is answered with that record's disposition instead: `Ledger row declined: <row> — <the reason the record gives for the rejection>`; it is no candidate for `judge-findings`, and it never raises the finding again. A closed row is neither a finding nor a `Declined to judge` line — it is no candidate for `judge-findings` and joins no record. Its closure is a fact about the code of the round that closed it, not a verdict carried forward: the ledger is the only carrier, so a later round answers the row again from the code as it then stands, and a fix that brings the condition back brings the row back as a finding.

Keep the reviewer's text, severity, and location whole and separate from the verdict: the caller passes them on as the reviewer's own output, so anything reworded here reaches its reader in place of the reviewer's claim. Return each verdict as `judge-findings` returned it, its fix or reason included and none of them reworded.

Verdicts carry the meanings `judge-findings`'s **Verdicts** gives them.

Alongside the findings, return whichever caveat **Reviewer prompt** asks for: a paths-only scope, or no requirements — and any `not measured` line `judge-findings` returned.
