---
name: review-findings
description: Use to review a findings report or a judgment report before it becomes the canonical record — an investigation's root-cause findings, a decision or ruling comment, or any report whose claims a later flow will act on. Reports findings; it never edits what it reviewed. Triggers on "review these findings", "review this report before I publish it", "is this conclusion backed", "check this before it goes on the issue".
---

# Review Findings

Use on a report whose deliverable is findings, once it is drafted and before it is published. This reviews what the report claims and what backs it, never the work that produced it and never the fix it might lead to.

## Orchestration model

**Every invocation owes exactly one clean — inline-clean by default; only a marked pass dispatches a reviewer and owes dispatched-clean instead.** Inline-clean is the default mandatory gate: the orchestrator checks the report against the three default lenses in the main loop in one pass, recording the verdict in chat per **Report**, and declares clean only on what the pass actually read. A dispatched pass goes out in a fresh context at the tier `using-dude`'s **Worker tier** sets for a marked worker, carrying the report, the question it answers, its stated sources, the lenses this pass covers, the edited scope, and the record of past rounds; the reviewer validates each candidate finding against the target and its sources under this skill's own **What counts as a finding** and returns the final blocking findings or clean, and the orchestrator reports the result without re-judging it. There is no skip path: one of the two cleans is required on every invocation. `review-plan` is not used here; nothing here dispatches a verdict worker.

The main loop is normally the same run that wrote the report under review, so its inline check rests on its own account of the evidence — which is why a dispatched reader in a fresh context stays the opt-in for the high-risk cases below, where a sweep cut short reads as "nothing found" and nothing but another reader catches it.

A run cannot re-judge what it never returned, and a sweep cut short is a failure of recall rather than of judgment, so where a dispatch case below holds nothing but another reader catches it.

## Target

One invocation reviews exactly one target, and **the caller declares it**: the findings or judgment report that is about to become the canonical record. The caller states the artifact, the question it answers, and the sources it rests on.

An `investigate-*` findings report and a ruling published as an issue comment differ in format only. The failure modes read for here — evidence that does not carry the claim, a sweep that stopped early, a hypothesis promoted without a measurement — are the same in both, so they are one target rather than two.

## What counts as a finding

One test admits everything this skill reports: **left as it is, would a reader acting on this record reach a wrong conclusion or take a wrong fix?** The record outlives the run that wrote it and is read as settled, so the reader in that test is not the author.

This test overrides the lenses. A lens names a failure mode to look for; naming one does not make every instance of it worth reporting. A caveat that could be worded more carefully, a section a reviewer would have ordered differently, a measurement reported to more precision than it warrants — none of these change what a reader does, so they are not findings, whatever lens surfaced them. Reviewer preference is never a finding here.

Both severities in **Severity** are blocking. There is no non-blocking tier: a finding that passes the test is resolved before the report is published, and anything that fails it is left unsaid rather than recorded as a note.

## Lenses

Six in total, three by default, and none of them lowers the bar in **What counts as a finding**. The default inline pass covers Reality (edited scope only), Evidence sufficiency (artifact presence only), and Hypothesis separation; Sweep completeness, Completeness, and Consistency run only in a dispatched pass, except a re-run after Critical handling, which covers all six lenses inline where neither (a) nor (d) applies. An initial pass runs inline with the default three, except where the caller declared dispatch case (a) or the orchestrator marked (d), which gives all six to its single reviewer; a re-run after an Important finding is scoped per **Caller contract**.

- **Evidence sufficiency** — whether each claim names its backing artifact: a `path:line` or a command plus its measured value per claim. Whether the artifact actually carries the claim is checked only in a dispatched pass, except the full-scope inline re-run after Critical handling where neither (a) nor (d) applies, which checks it inline.
- **Sweep completeness** — every claim of absence, exhaustiveness, or "only" is met against the trace the sweep left, not by re-running the sweep itself: the command issued, the count it returned, and no `| head` or page cut between the two. A claim whose trace cannot be pointed at is a finding.
- **Hypothesis separation** — whether anything stated as a conclusion is in fact an unconfirmed hypothesis, per `using-dude`'s **Investigation workflow**. This is that rule checked by a reader rather than by the run that has been living with the hypothesis.
- **Completeness** — whether the explanation accounts for the symptom as observed: its magnitude, its timing, and its scope, or the unknowns documented in place of them. This is the `investigate-*` exit condition re-read by someone who did not decide it was met.
- **Consistency** — claims that contradict each other, a timeline that disagrees with the narrative, terminology that shifts meaning between sections, a summary that overstates what the body establishes.
- **Reality** — mismatch with the system as it is, limited to the edited scope: a version, config, code path, or constraint the report describes wrongly within what the report changed.

A re-run after Critical handling covers all six lenses inline where neither (a) nor (d) applies.

*Skip* **Necessity**, **Executability**, **Risk** and **Assumptions**, and say so in the report: the work this report may propose is not reviewed here (it enters `plan-work`), so there is nothing for the first three to bite on, and what a report takes for granted is Evidence sufficiency's business here.

## Severity

Each finding returns lens, severity, claim (one sentence), evidence (`path:line` or the quoted line), and suggested change. Severity says where the remedy lives, not how urgent it is. Report "no findings" explicitly rather than inventing one.

- **Critical** — the conclusion itself is unbacked. No edit to the report fixes it: the remedy lives outside a report edit, per **Caller contract**.
- **Important** — what was measured is described wrongly. Editing the report resolves it.

## Pass

1. Gather the inputs: the target report, the question it answers, its stated sources, the lenses this pass covers, the edited scope (the whole report on an initial pass and on a re-run after Critical handling; the actual report edits on a re-run after an Important finding), and the record of earlier passes if the caller supplied one.
2. Run the inline pass with the lenses this pass covers — the default three, except a re-run after an Important finding, which is scoped per **Caller contract**, and except a re-run after Critical handling, which covers all six lenses inline where neither (a) nor (d) applies. Confine every search to the project root or narrower. Where the caller declared dispatch case (a) or the orchestrator marked (d) per **Caller contract**, dispatch exactly one reviewer with all six lenses instead, except a re-run after an Important finding where the same round did not also return Critical, which stays scoped per **Caller contract**; the reviewer validates each candidate finding against the target and its sources under **What counts as a finding** and returns the final blocking findings or clean.
3. Judge an inline pass clean or blocking under **What counts as a finding** (inline-clean); report a dispatched pass as returned without re-judging it (dispatched-clean or its blocking findings).
4. Report per **Report**, and stop there — revising and re-running are the caller's job.

## Report

Report to the caller in chat, never to GitHub, per `using-dude`'s **Stage boundaries**. Report, for this pass: the target reviewed, the fan-out used (none inline, one dispatched), any lens skipped with why, the blocking findings per **Severity**, the round history carried forward, and the verdict — the required clean (inline-clean, or dispatched-clean where a dispatch case holds), or the blocking findings that remain, flagging any Critical separately.

## Caller contract

This holds for every caller, rather than being defined at each call site. The gate always runs and is never skipped; what varies by risk is which clean it owes — inline-clean by default, dispatched-clean where one of the cases below holds. The caller declares whether (a) applies or records the inline-clean; the orchestrator marks (d) in the hand-off summary.

- **Dispatch where one of these holds** — the required clean is dispatched-clean:
  - (a) the report claims absence, exhaustiveness, or "only" — a cut-short sweep hands back "nothing found", which neither the orchestrator nor any later reader can tell from an absence;
  - (d) the report feeds external publication — public changelog, postmortem, or user-facing doc, excluding issue comments and chat records. The orchestrator judges this and records it in the hand-off summary.

- **An anomaly-cause determination and a performance-bottleneck determination stay inline-clean for the retired (b)/(c) routes; where (a) or (d) holds, dispatched-clean is still required.** Reports that would previously have dispatched under (b) and (c) now owe the default three-lens inline-clean instead; this gate relaxation is accepted, trading Sweep completeness, Completeness, and Consistency coverage on those reports for speed.

- **One round is one pass plus the caller's fold-in.** This skill never re-reviews on its own; revising the report and re-running belong to the caller.
- **After an Important finding**, re-run only the lens that produced it plus Reality, scoped to the edited scope.
- **A Critical finding returns to the evidence owner of the work that produced the target.** Every `investigate-*` caller returns to its evidence gathering / point settlement; a caller with no owning procedure asks a person where to get the missing evidence and stops.
- **Where re-measurement is impossible**, restate the conclusion as unsettled / not measured with what would settle it, leaving no unsupported certainty.
- **After Critical handling** — new evidence, or a revision to unsettled / not measured — the next pass is full scope, preserving the outer loop's total round count and same-finding history. Where the same round also returned an Important finding, this rule governs the next pass.
- **Two findings are the same** when a later pass faults the same claim on the same grounds, however the wording moved — including a claim restated after an edit meant to resolve it.
- **Stopping** is `using-dude`'s **Loop convergence**.
- **Nothing is published until the required clean comes back** — inline-clean, or dispatched-clean where a dispatch case above holds. Report each round to the caller in chat and never to GitHub, per `using-dude`'s **Stage boundaries**.
