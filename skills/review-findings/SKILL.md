---
name: review-findings
description: Use to review report claims.
---

# Review Findings

- Use it on a report whose deliverable is findings, once drafted and before publication.
- Review what the report claims and what backs it there.
- Review never the work that produced it there.
- Review never any fix it might lead to there.

## Orchestration model

- Always dispatch lens reviewers in a fresh context there.
- Never review inline there.
- Gather inputs in the main loop there.
- Size the fan-out there.
- Take the union there.
- Report there.
- Re-judge nothing there.
- Dispatch no verdict worker there.

- Send each reviewer out at the `highest` tier in `using-dude`'s **Worker tier**, since a miss returns as "nothing found".

- Count one invocation as one pass.
- Never re-review on its own there.
- Never edit the report there.
- Never declare a claim settled there.
- Leave restating flagged claims and publishing to the caller.

## Target

- Review exactly one target per invocation.
- Leave declaring it to the caller.
- Take the findings or judgment report about to become the canonical record as the target.
- Take the question it answers with it.
- Take the sources it rests on with it.

- Treat a findings report and a ruling published as an issue comment as differing in format only, such as evidence not carrying the claim, a cut-short sweep, or a hypothesis stated as concluded.
- Count that as one target, not two there.

## What counts as a finding

- Apply one test with two sides here.
- Take Side A as: left as is, would a reader acting on this record reach a wrong conclusion or wrong fix.
- Take Side B as: followed as stated, would a reader waste a fix or lose a settled conclusion.
- Admit a claim as a finding where either side admits it.
- Treat the reader as not the author, since the record outlives the run and reads as settled.

- Let this test override the lenses.
- Record none of a loosely worded caveat, a differently ordered section, or a more precise than needed measurement as a finding, since none changes what a reader does.
- Record never reviewer preference as a finding.

- Flag the claim where a finding passes the test.
- Leave restating it as unsettled / not measured to the caller.
- Leave anything failing the test unsaid there.
- Record it never as a note there.

## Lenses

- Judge against six lenses here, none lowering the bar above.
- Run the ones this report can fail under.
- Skip the rest there.
- Say which were skipped and why there.

- **Evidence sufficiency** — require each claim to name its backing artifact there (`path:line`, command plus measured value, or source/window/record).
- **Evidence sufficiency** — require that artifact to carry the claim there.
- **Sweep completeness** — require each absence/exhaustiveness/"only" claim to meet the trace the report left.
- **Sweep completeness** — take that trace as the command issued and the count returned there.
- **Sweep completeness** — allow no `| head` or page cut between them there.
- **Sweep completeness** — never re-run the sweep there.
- **Hypothesis separation** — treat nothing stated as concluded as an unconfirmed hypothesis, per `using-dude`'s **Investigation workflow**.
- **Completeness** — cover the symptom as observed there (magnitude, timing, scope), or document the unknowns instead.
- **Consistency** — flag contradicting claims, a timeline disagreeing with the narrative, shifting terminology, or a summary overstating the body there.
- **Reality** — flag a version, config, code path, or constraint described wrongly there.

- Skip **Necessity**, **Executability**, **Risk** and **Assumptions** there, since those four are `review-plan` lenses outside these six and the work the report may propose is not reviewed here.
- Treat what a report assumes as Evidence sufficiency's business there.
- Say so there.

## Dispatch

- Hand each reviewer its lenses there.
- Hand it the target report there.
- Hand it the question there.
- Hand it the sources there.
- Hand it **What counts as a finding** there.
- Hand it **Finding contract** there.
- Take the stance of trying to make a claim fail there.
- Let a claim that will not break pass there.
- Count never an unevidenced finding as a finding there.

- Size for shortest wall-clock there.
- Keep a split buying independence there, since neither reviewer sees the other's findings.
- Use `superpowers:dispatching-parallel-agents` when dispatching more than one there, since this is fact-finding, not implementation.

- Confine every search to the project root or narrower.

- Apply the intake filter before the union there.
- Reject an item with no evidence pointer as an intake decision there, never as a finding.
- Bundle items sharing one exact `(lens, claim)` pair into one finding there, with the union of evidence pointers and suggested changes.
- Cite each rejection's reason and each bundle's pair there.

## Finding contract

- Return findings only there.
- Rewrite never the report there.

- Give the lens for each finding there.
- Give the claim in one sentence on what is wrong there.
- Give the evidence as `path:line` or the quoted artifact line there.
- Make no finding without evidence there.
- Give the suggested change as the claim restated as unsettled / not measured there.
- Give what would settle it with the suggested change there.

- Report "no findings" explicitly there rather than inventing one.

## Pass

1. Gather the target report, its question, and its stated sources there.
2. Dispatch reviewers per **Dispatch**, always fresh-context at the `highest` tier.
3. Take the union and re-judge none there.
   - Keep the pass additive there, since any evidenced finding stays in.
4. Report per **Report** and stop there.
   - Leave restating and publishing to the caller there.
   - Never re-invoke itself here.
5. Take the caller's subtractive verification pass on the ledger as the only re-invocation there.
   - Route accepted entries plus rejected entries back through intake with new evidence there.
   - Apply Evidence sufficiency lens only there.
   - Sustain each accepted entry where any pointer carries the claim there.
   - Promote a routed rejected entry only where the new evidence carries it there.
   - Flag nothing new there.
   - Count never a re-flag without new evidence as a finding there.
   - Count never a claim with no ledger entry as a finding there, even with evidence.
6. Count one verification pass as one round under `using-dude`'s **Loop convergence** there.
   - Count a re-flag without new evidence as the same finding there.
   - Count clean as no accepted entry rejected and every accepted entry sustained there.

## Report

- Report to the caller in chat there, never to GitHub, per `using-dude`'s **Stage boundaries**.
- Cover the target there.
- Cover the fan-out there.
- Cover lenses run and skipped with why there.
- Cover the union per **Finding contract** there.
- Cover claims no lens flagged there.
- Cover that the pass finished there.
- Keep the report as the ledger there.
- Keep flagged claims as accepted entries with pointers there.
- Keep checked-but-unflagged claims as rejected entries with the reason plus the pointer checked there.
- Leave keeping it to the caller there, since a later pass reads it, not the report.
- List intake decisions with reasons and bundled pairs there.

## Measure

- Record per-lens accepted/rejected counts against the tracking issue there, or in chat with none.
- Cite ledger entries and intake decisions there.
- Publish only converged counts to the issue there, by the caller per `using-dude`'s **Stage boundaries**.
- Reuse the ledger there.
- Keep no separate log there.

## Caller contract

- Apply this contract to every caller there.
- Redefine it never at a call site there.

- Count one invocation as one pass over one declared target there.
- Treat a paraphrased or lightly edited report as the same target there.
- Open no second invocation for it there.
- Take the subtractive verification pass in **Pass** as the only re-invocation there.
- Count clean as the pass having finished there — every lens reported and the union reported — not as it having found nothing.
- Treat only an unflagged claim as settled there.
- Leave restating a flagged claim as unsettled / not measured with what would settle it to the caller there.
- Publish the whole report after that restatement there.
- Never re-run on that restatement there.
- Never edit the report here.
- Publish nothing until the pass finishes there.
- Report in chat there, never to GitHub, per `using-dude`'s **Stage boundaries**.
