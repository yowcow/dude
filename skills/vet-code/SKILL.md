---
name: vet-code
description: Use as a component when another skill needs one round of code review findings, each already judged.
---

# Vet Code

- Leave resolving the scope to the caller.
- Leave applying or verifying a fix to the caller.
- Leave deciding whether another round runs to the caller.
- Leave posting anything anywhere to the caller.
- Touch neither the code nor GitHub here.

## Orchestration model

- Dispatch one read-only reviewer here, since judging goes to `judge-findings`.
- Let nothing else leave the main loop.
- Dispatch the reviewer as a read-only worker through `superpowers:requesting-code-review` with the prompt **Reviewer prompt** defines.
- Take back that template's output from the reviewer.
- Let the reviewer edit no code.
- Let the reviewer run none of the project's checks.
- Let the reviewer commit nothing.
- Send the reviewer out at the `high` tier in `using-dude`'s **Worker tier**, since a finding it does not return comes back as "nothing found" and the caller reads that as clean.
- Dispatch one reviewer per invocation, fresh each time, since the fan-out here is fixed at one.
  - A diff does not warrant more.
- Once the reviewer returns, hand `judge-findings` every Issues finding as a candidate.
- Hand every Declined to judge line as a candidate too.
- Hand the scope and the requirements the reviewer got.
- Hand the earlier rounds' record.
- Hand every Declined line however the earlier rounds' record holds it, since that record travels as context and never as a filter.
  - A line dropped as already judged never reaches the judge.
- Hand the template's "The spec is a vision document" paragraph verbatim as the acceptance criteria.
- Treat a candidate sitting outside the plan or spec as why the reviewer set it aside, never as a ground to reject it.
- Treat code unchanged since the previous round as no ground to reject either, when the candidate claims something about that code.
- Treat a line that only discloses part of the scope as unreviewed, never as such a candidate.
- Keep the fresh context a read-only worker buys, since it reads the code without having written it and is not anchored on why the code ended up this way.

## Reviewer prompt

- Take `superpowers:requesting-code-review` as the dispatch mechanism.
- Use that procedure's template verbatim with its four placeholders filled.
- Change nothing in the template body.
- Put what the reviewer needs beyond the template inside `PLAN_OR_REQUIREMENTS`, since a placeholder's content is the caller's to write.
- Hand the scope in one of these four shapes.

- **a committed range** — the two SHAs bounding it.
- Fill `BASE_SHA` and `HEAD_SHA` with them.
- **uncommitted changes** — where they are, staged, unstaged, and untracked alike.
- **paths with no range** — the paths themselves, and that the review covers their current state on this checkout rather than a diff.
- Return the same caveat with the findings, since nothing constrains the review to recent change and the findings may be about code this work never touched.
- **a PR** — the range the caller resolved for it, handed over as a committed range.
- Review that diff locally, since that is this skill's job.
- Invent no SHAs.
- Where the scope has none, fill both `BASE_SHA` and `HEAD_SHA` with `N/A`.
**What was implemented** fills `DESCRIPTION` as follows.
- Describe what the change does.
- For a paths-only scope, describe what the code is for.
**The requirements** fill `PLAN_OR_REQUIREMENTS` as follows.
- Hand the entry artifact where the caller has one, with the plan's location beside it where one exists, and otherwise the original request.
- Where there is none, say so there, since the review then runs against the repository's own standards and the code's evident intent.
- Return that statement with the findings too, since a reader of the caller's report otherwise cannot tell plan alignment was not checked.
- After that, write the following in the same placeholder as plain instructions, each only when it applies.

- **Range shape** — for uncommitted changes or paths with no range, restate the scope as its shape above describes it.
- Say there that the Git Range to Review section does not apply and is to be ignored, its diff commands included.
- For uncommitted changes, read staged and unstaged changes together against HEAD.
- Read untracked files separately.
- **Worktree** — for uncommitted changes, review this checkout's current dirty state.
- Create no worktree there, since a worktree holds a revision and these changes are in none.
- For paths with no range, review this checkout's current state.
- Create no worktree there either.
- **Read-root** — when the caller's scope includes one, treat the bound directory as the only place to read and search the head.
- Let it outrank the template's this-checkout for this dispatch.
- Let it outrank any instruction to create a worktree.
- Let it outrank the project-root search confine.
- Confine every search to that directory.
- **Ledger rows** — when the caller hands any over, answer each row against the code as it now stands.
- Keep the row with its answer.
- Answer the finding it is and its severity, or that it no longer stands and why.
- Write never a `Declined to judge` line for a ledger row.
- Let ledger rows narrow nothing, since the scope shape stays the caller's.
- Cover the whole scope at every severity still, as without them.
- **Purpose** — only when the caller says the requirements include a settled purpose, the problem the change exists to solve, compare the means with that purpose.
- Name what the means gives up where a way to keep it exists, such as looser coupling or less room for defects.
- Rate a loss of that kind by what it costs, never as Minor because the code works.
- **Earlier rounds** — from the caller's second round on, take findings accepted and fixed, and findings or Declined to judge lines rejected with the reason.
- Let the record narrow the review in nothing, since it covers the whole scope at every severity with places unchanged since the previous round included.
- Let the record stop only a finding it holds as rejected from being raised again.
- Raise a finding accepted and fixed that still stands again.
- Treat a reviewer not shown the rejections as re-litigating them.
- **Confine** — keep every search at the project root or narrower.
- **Tests** — answer "All tests passing?" from the diff alone.
- Run neither the project's checks nor any code from the range under review.
- Say the checks were not run.
- Close with one sentence: where these instructions and the template disagree, these win.

## Output

- Receive the template output as-is.
- Treat Strengths, Recommendations, and Assessment as not findings.
- Treat Assessment Ready to merge as not this skill declaring the code clean, since clean remains the caller's from whether blocking findings exist.
- For each finding, return the finding as the reviewer stated it.
- Return its severity — Critical, Important, or Minor.
- Return its location.
- Return its verdict: an `accept` with its fix, a `reject` with its reason, or `needs-user` with its question.
- Reword none of them.
- Put no value beside them.
- For each Declined to judge line, return the line as the reviewer stated it.
- Return its verdict in the same three tokens.
- Return whether it stayed declined or became a finding.
- Keep a line that became a finding in the finding list too, for its severity and verdict.
- For each ledger row the caller handed over, take only lines carrying the execution method's `Ruling:` marker, and deferred-minor lines where the caller kept them.
- Return the finding it became in the finding list with the row it came from kept.
- Or return one line `Ledger row closed: <row> — <why it no longer stands>`.
- Where the earlier rounds' record already holds the row's finding as rejected, answer with that record's disposition instead: `Ledger row declined: <row> — <the reason the record gives for the rejection>`.
- Make such a row no candidate for `judge-findings`.
- Raise its finding never again.
- Treat a closed row as neither a finding nor a `Declined to judge` line.
- Make it no candidate for `judge-findings` and join it to no record.
- Treat its closure as a fact about the code of the round that closed it, never as a verdict carried forward, since the ledger is the only carrier.
- Answer the row again from the code as it then stands in a later round.
- Bring the row back as a finding where a fix brings the condition back.
- Keep the reviewer's text, severity, and location whole and separate from the verdict, since the caller passes them on as the reviewer's own output and anything reworded here reaches its reader in place of the reviewer's claim.
- Return each verdict as `judge-findings` returned it, its fix or reason included and none of them reworded.
- Give Verdicts the meanings `judge-findings`'s **Verdicts** gives them.
- Return alongside the findings whichever caveat **Reviewer prompt** asks for: a paths-only scope, or no requirements.
- Return any `not measured` line `judge-findings` returned.
