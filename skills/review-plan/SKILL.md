---
name: review-plan
description: Use to review a planning artifact.
---

# Review Plan

- Use on planning work before code.
- Use it on its revision too.
- Review the plan there, never the code.

## Orchestration model

- Dispatch read-only reviewers here, since judging goes to `judge-findings`.
- Keep everything else in the main loop.
- Gather inputs there.
- Size the fan-out there.
- Write the report there.
- Call the pass clean there.
- Take findings and a hand-back from a reviewer.
- Let a reviewer edit nothing.
- Let a reviewer declare nothing clean.
- Let a reviewer run no project check.
- Let **Dispatch** size the fan-out.
- Send each reviewer out at the `high` tier in `using-dude`'s **Worker tier**, since a missed design flaw flows into implementation and every later gate reads the implementation, never the plan.
- Judge nothing in the main loop either.
- Write the report in the orchestrator from `judge-findings` verdicts.
- Re-judge none there.
- Count one invocation as one pass.
- Re-review never on its own there.
- Leave revising and re-running to the caller.

## What counts as a finding

- Admit everything through one test.
- Ask there: left as it is, would this make the implementation stall or go wrong?
- Count a gap sending an implementer down the wrong path as a finding.
- Count leaving them stuck as a finding.
- Count producing the wrong result as a finding.
- Count nothing else as a finding.
- Let this override the lenses.
- Count drifting terminology that misleads nobody as never a finding.
- Count better wording as never a finding.
- Count a differently organised section as never a finding.
- Count reviewer preference as never a finding.
- Count prose and formatting only where the implementer cannot tell what the plan means.
- Keep no non-blocking tier.
- Resolve a passing finding before implementation.
- Leave anything failing it unsaid.
- Record it never as a note.
- Count a question no lens can judge without a measurement as a finding against the plan line it leaves unsupported where the answer could change what the plan instructs.
- Quote that line as its evidence.
- Let `judge-findings` take it to `needs-user` there.
- Put only a question whose answer cannot change the plan on the **not measured** line.
- Put what would settle it there too.

## Targets

- Review exactly one target per invocation.
- Let the caller declare which.
- Let the target set lenses and fan-out.
- Take a **TODO list** as the design plus numbered PR-sized items.
- Apply **Necessity, Completeness, Consistency, Reality, Risk** there.
  - *Skip* **Assumptions** and **Executability** there, since no task detail yet for either to bite on.
- Take an **Implementation plan** as one PR's detail.
- Apply **Completeness, Consistency, Reality, Assumptions, Executability, Risk** there.
  - *Skip* **Necessity** there, since it was settled when the TODO list was reviewed.
  - Raise past-scope detail under Consistency against the item's completion criteria, since it is not Necessity reopening.
  - Cover error paths, migration and rollback, and ordering under Completeness and Consistency too.

## Lenses

- Treat each lens as a failure mode.
- Let none lower the bar above.
- Let **Targets** select which apply.
- Let **Dispatch** select how many reviewers.
- Check **Necessity** for whether the work is warranted: unrequested steps, grown scope, a smaller path, an existing feature covering it.
- Check **Completeness** for uncovered requirements: missing edges, error paths, migration, rollback, docs.
  - On an implementation plan, flag a task with no verification step too.
  - On a TODO list, flag an item with no completion criteria too.
  - Never flag a missing verification command on a TODO list, since it is contractually forbidden there and flagging it manufactures a finding per item.
- Check **Consistency** for contradicting steps, ordering or dependency errors, state no earlier task produces, and drifting terms.
- Check **Reality** for mismatch with the repo: ignored failures, constraints, config.
- Check **Assumptions** for unchecked preconditions, unverified dependency behaviour, assumed environment, permissions, and data shape.
- List each assumption there, marked verified or unverified.
- Let Reality catch what the repo contradicts.
- Let Assumptions catch what nobody has confirmed either way.
- Check **Executability** for tasks too large or vague to implement and verify alone, shared files breaking independence, verification that would not show the change, and a named command with unspecified result-testing.
- Check **Risk** for blast radius, compatibility, data and security, and half-landed state.
- On a TODO list, check under Risk whether every intermediate state holds with only some PRs merged too.

## Dispatch

- Hand each reviewer its lenses, the artifact, the original request, and the paths it touches.
- Take trying to make the plan fail as the stance.
- Let one that will not break pass.
- Count an unevidenced finding as no finding.
- Keep the dispatch small, since both targets are small.
- Take the whole lens list with one reviewer by default.
- Take two reviewers when large, risky, or spanning subsystems.
- Split artifact-only lenses from repo-reading ones there, since the split buys independence.
- Use `superpowers:dispatching-parallel-agents` when dispatching more than one, since this is fact-finding rather than implementation.
- On a revision, dispatch only lenses that produced an accepted finding, plus Reality.
- Let the caller hand the earlier pass record there.
- Scope a revision to the resolving edits.
- Give no fresh look to a rewording that changes no instruction.
- Pass the record so rejected findings are not re-litigated.
- Skip a lens only when inapplicable, saying which and why.

## Finding contract

- Return findings only, never a rewritten plan.
- Return each finding with its lens and its severity, since that is where the remedy lives.
- Count **Critical** as the design being wrong, with no plan edit fixing it and re-approval needed.
- Count **Important** as the plan being wrong, with an edit fixing it.
- Let both block implementation.
- State the claim in one sentence on what is wrong.
- Give evidence as `path:line` or the quoted artifact line.
- Count no evidence as no finding.
- Say what it should say instead as the suggested change.
- Give a **not measured** question no lens could judge that changes nothing the plan instructs, plus what would settle it.
- Report "no findings" explicitly.
- Confine every search to the project root or narrower.

## Pass

1. Gather the declared target, the artifact, the original request, the paths, and any earlier pass record.
2. Dispatch reviewers per **Dispatch**.
3. Hand findings to `judge-findings` and take back verdicts.
   - Judge the plan and repo against the original request there, under **What counts as a finding**.
   - Settle a measurement-route `needs-user` before the person route.
   - Let the caller take that one bounded measurement there, record it, and hand the finding back.
   - Run no project check in this pass.
   - Send to a person only what the caller may not spend.
4. Report per **Report** and stop.
   - Leave revising and re-reviewing to the caller.
- Hold clean per `using-dude`'s **Loop convergence** loop-clean as no surviving finding.
- Take its route for a surviving `needs-user`.
- Bring measurement-route findings back with the record for re-judging.
- Take person-route findings to a person.
- Settle no plan edit first there.
- Re-run never to clear a `needs-user`, since **Dispatch** scopes every lens to resolving edits and a `needs-user` produced none, so the re-run returns clean over an unanswered question.
- Return a settled answer as an ordinary revision with that finding carried accepted-and-fixed.

## Report

- Report to the caller in chat, never to GitHub, per `using-dude`'s **Stage boundaries**.
- Report the target there.
- Report the fan-out there.
- Report lenses skipped with why.
- Report accepted findings with lens, severity, evidence, and suggested change.
- Report rejected findings with reasons.
- Report `needs-user` findings with routes.
- Report **not measured** lines.
- Report the verdict: clean, or the blocking findings left.
- Flag any Critical separately there.
