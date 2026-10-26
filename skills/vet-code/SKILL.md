---
name: vet-code
description: Use as a component when another skill needs one round of code review findings, each already judged.
---

# Vet Code

Resolving the scope, applying or verifying a fix, deciding whether another round runs, and posting anything anywhere are the caller's. This skill touches neither the code nor GitHub.

## Orchestration model

**This skill dispatches one read-only reviewer; judging goes to `judge-findings`.** Nothing else leaves the main loop.

- The reviewer is a read-only worker, dispatched through `superpowers:requesting-code-review` with the prompt **Reviewer prompt** defines. It returns that template's output. It never edits code, never runs the project's checks, and never commits. It reads the measurement record its prompt carries, per `using-dude`'s **Measurement records**, and where that record does not cover the question, it says what would have to be measured.
- The reviewer goes out at the `high` tier in `using-dude`'s **Worker tier**: a finding it doesn't return comes back as "nothing found", and the caller reads that as clean.
- One reviewer per invocation, fresh each time — the fan-out here is fixed at one, because a diff doesn't warrant more.
- Once the reviewer returns, hand `judge-findings` every Issues finding, and every Declined to judge line as a candidate, with the scope and requirements the reviewer got, the earlier rounds' record, and the measurement record's path when one was passed. Every Declined line is handed over however the earlier rounds' record holds it, and that record travels as context, never as a filter; a line dropped as already judged never reaches the judge. Where the caller runs under the `implement-work` completion gate, it writes the handoff whole into `judge-input-<round>.md` per `implement-work`'s `references/measurement-record.md` before dispatching, and writes the empty input file with its identity even when no items mean no worker is dispatched. As the acceptance criteria, hand it the template's "The spec is a vision document" paragraph verbatim, plus: a candidate sitting outside the plan or spec is why the reviewer set it aside, not a ground to reject it, and neither is the code being unchanged since the previous round when the candidate claims something about that code. A line that only discloses part of the scope went unreviewed is not such a candidate.
- What a read-only worker buys is a fresh context: it reads the code without having written it, so it is not anchored on why the code ended up this way.

## Reviewer prompt

`superpowers:requesting-code-review` is the dispatch mechanism. The prompt body is that procedure's template. The prompt is complete only when the template's prompt is verbatim except placeholder fill, the replacements below, the read-root with its precedence passed beside the SHAs, and the measurement record's path with its instruction to read it. The caller's four inputs fill placeholders and may append after the template; a fifth, the ledger rows, is optional and appends after it too.

The caller hands the scope in one of these four shapes:

- **a committed range** — the two SHAs bounding it. Fill `BASE_SHA` and `HEAD_SHA` only.
- **uncommitted changes** — where they are: staged, unstaged, and untracked alike. Do not send the reviewer to a worktree of its own here — a worktree holds a revision, and these changes are in none.
- **paths with no range** — the paths themselves, and that the review covers their current state on this checkout rather than a diff. Return the same caveat with the findings: nothing constrains the review to recent change, so the findings may be about code this work never touched.
- **a PR** — the range the caller resolved for it, handed over as a committed range. Reviewing that diff locally is this skill's job.

For uncommitted changes or paths with no range, replacing the Git Range to Review section as a whole (its two diff command lines included) with that shape's description is the fill. Do not invent SHAs. From that same constructed prompt, drop the template Read-Only Review sentence that tells the reviewer to create a worktree, or replace it — for uncommitted changes: review this checkout's current dirty state; do not create a worktree; for paths with no range: review this checkout's current state; do not create a worktree.

When the caller's scope includes a read-root — a directory already bound as the only place to read and search the head — pass it beside the filled SHAs and tell the reviewer that for that dispatch it outranks the template's this-checkout, any instruction that the reviewer create its own worktree, and the project-root search confine: every search is confined to that directory.

When the caller has a measurement record covering the scope, pass its path beside the read-root and the filled SHAs, and tell the reviewer to read it instead of running the checks itself, and where it does not cover a question, to say what would have to be measured. A record outside the read-root is still readable because the path names it.

**What was implemented** fills `DESCRIPTION` — what the change does, or for a paths-only scope what the code is for.

**The requirements** fill `PLAN_OR_REQUIREMENTS` — the entry artifact where the caller has one, with the plan's location beside it where one exists, and otherwise the original request. When there is none, say so in that placeholder: the review then runs against the repository's own standards and the code's evident intent. Return that with the findings too, so a reader of the caller's report knows plan alignment was not checked.

**The ledger rows** — when the caller hands any over, append them after the template with one instruction: answer each row against the code as it now stands, keeping the row with its answer — the finding it is and its severity, or that it no longer stands and why, and never as a `Declined to judge` line. They narrow nothing: the scope shape is the caller's and stays as it is, and every search still covers the whole scope at every severity, as it would without them.

After the template, append only these viewpoint extras:

- **Optionally, that the requirements include a settled purpose** — the problem the change exists to solve. Only when the caller says so, tell the reviewer to compare the means with that purpose and to name what the means gives up where a way to keep it exists, such as looser coupling or less room for defects. A loss of that kind is rated by what it costs, not Minor because the code works.
- **The earlier rounds** — from the caller's second round on, findings accepted and fixed, findings accepted and recorded without a fix, findings rejected with the reason, and Declined to judge lines rejected with the reason. The record does not narrow the review: tell the reviewer to cover the whole scope at every severity, places unchanged since the previous round included, and that the record stops only a finding it holds as rejected, or as accepted and recorded without a fix, from being raised again; a finding accepted and fixed that still stands is raised again. A reviewer not shown the rejections re-litigates them.

Also after the template: Confine every search to the project root or narrower. Answer "All tests passing?" from the diff alone and from the measurement record when the prompt carries one: run neither the project's checks nor any code from the range under review, and say the checks were not run.

## Output

Receive the template output as-is. Strengths, Recommendations, and Assessment are not findings. Assessment Ready to merge is not this skill declaring the code clean; clean remains the caller's, from whether blocking findings exist.

For each finding: the finding as the reviewer stated it, its severity — Critical, Important, or Minor — its location, and its verdict, an `accept` with its fix, its value, and that value's reason; for each Declined to judge line, the line as the reviewer stated it, its verdict, and whether it stayed declined or became a finding, with a line that became a finding staying in the finding list too, for its severity and verdict.

For each ledger row the caller handed over: the finding it became, returned in the finding list with the row it came from kept, or one line `Ledger row closed: <row> — <why it no longer stands>`. A row whose finding the earlier rounds' record already holds as rejected, or as accepted and recorded without a fix, is answered with that record's disposition instead: `Ledger row declined: <row> — <the reason the record gives for the rejection>`, or `Ledger row recorded: <row> — <the finding it became, value \`record\` and why, and where it is recorded>`; neither is a candidate for `judge-findings`, and neither raises the finding again. A closed row is neither a finding nor a `Declined to judge` line — it is no candidate for `judge-findings`. Its closure is a fact about the code of the round that closed it, not a verdict carried forward: the ledger is the only carrier, so a later round answers the row again from the code as it then stands, and a fix that brings the condition back brings the row back as a finding.

Keep the reviewer's text, severity, and location whole and separate from the verdict: the caller passes them on as the reviewer's own output, so anything reworded here reaches its reader in place of the reviewer's claim. Return each verdict as `judge-findings` returned it, its fix, value, and reason included and none of them reworded: a caller reads a non-blocking `accept` that arrives with no value as one never to fix.

Verdicts carry the meanings `judge-findings`'s **Verdicts** gives them.

Alongside the findings, return whichever caveat **Reviewer prompt** asks for: a paths-only scope, or no requirements — and a `not measured` line for any question the record did not cover, naming what would have to be measured.
