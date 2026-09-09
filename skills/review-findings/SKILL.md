---
name: review-findings
description: Use to review a findings report or a judgment report before it becomes the canonical record — an investigation's root-cause findings, a decision or ruling comment, or any report whose claims a later flow will act on. Reports findings; it never edits what it reviewed. Triggers on "review these findings", "review this report before I publish it", "is this conclusion backed", "check this before it goes on the issue".
---

# Review Findings

Use on a report whose deliverable is findings, once it is drafted and before it is published. This reviews what the report claims and what backs it, never the work that produced it and never the fix it might lead to.

## Orchestration model

The mechanism is `review-plan`'s **Orchestration model**, and it applies here unchanged, with this skill's **Lenses** in place of that skill's list. What that means at this gate, because the temptation runs the other way: **both the lens sweep and every verdict are dispatched to workers**, on every round. The main loop is normally the same run that wrote the report under review, so a lens read or a verdict reached there rests on that run's own account of its evidence — which is precisely what a dispatched reader in a fresh context is bought to escape. An orchestrator that reads the report against the six lenses itself has not run this gate.

A run cannot re-judge what it never returned, and a sweep cut short is a failure of recall rather than of judgment, so nothing but another reader catches it.

## Target

One invocation reviews exactly one target, and **the caller declares it**: the findings or judgment report that is about to become the canonical record. The caller states the artifact, the question it answers, and the sources it rests on.

An `investigate-*` findings report and a ruling published as an issue comment differ in format only. The failure modes read for here — evidence that does not carry the claim, a sweep that stopped early, a hypothesis promoted without a measurement — are the same in both, so they are one target rather than two.

## What counts as a finding

One test admits everything this skill reports: **left as it is, would a reader acting on this record reach a wrong conclusion or take a wrong fix?** The record outlives the run that wrote it and is read as settled, so the reader in that test is not the author.

This test overrides the lenses. A lens names a failure mode to look for; naming one does not make every instance of it worth reporting. A caveat that could be worded more carefully, a section a reviewer would have ordered differently, a measurement reported to more precision than it warrants — none of these change what a reader does, so they are not findings, whatever lens surfaced them. Reviewer preference is never a finding here.

Both severities in **Severity** block. There is no non-blocking tier: a finding that passes the test is resolved before the report is published, and anything that fails it is left unsaid rather than recorded as a note.

## Lenses

Six, and none of them lowers the bar in **What counts as a finding**. How many reviewers they map to comes from `review-plan`'s **Dispatch**; where that section offers a two-way split, the line here is between the lenses that need only the report and its stated sources and the ones that need to re-read the sources themselves.

- **Evidence sufficiency** — whether each claim's stated evidence actually carries it: a conclusion resting on a sample, a single occurrence, or a correlation presented as though it were the measurement; a number with no command, window, or source behind it.
- **Sweep completeness** — every claim of absence, exhaustiveness, or "only" is met with the sweep that produced it: whether the sweep ran to completion and its whole output was read, rather than a truncated or paged view of it. A claim whose sweep cannot be pointed at is a finding.
- **Hypothesis separation** — whether anything stated as a conclusion is in fact an unconfirmed hypothesis, per `using-dude`'s **Investigation workflow**. This is that rule checked by a reader rather than by the run that has been living with the hypothesis.
- **Completeness** — whether the explanation accounts for the symptom as observed: its magnitude, its timing, and its scope, or the unknowns documented in place of them. This is the `investigate-*` exit condition re-read by someone who did not decide it was met.
- **Consistency** — claims that contradict each other, a timeline that disagrees with the narrative, terminology that shifts meaning between sections, a summary that overstates what the body establishes.
- **Reality** — mismatch with the system as it is: a version, config, code path, or constraint the report describes wrongly.

*Skip* **Necessity**, **Executability**, **Risk** and **Assumptions**, and say so in the report: this target proposes no work, so there is nothing for the first three to bite on, and what a report takes for granted is Evidence sufficiency's business here.

## Severity

`review-plan`'s **Finding contract** governs what a reviewer returns and applies unchanged, except that severity means this instead — and, as there, it says where the remedy lives rather than how urgent it is. Where that section sends a reviewer to **What counts as a finding** ("both block implementation"), the test it resolves to is this skill's own, not `review-plan`'s.

- **Critical** — the conclusion itself is unbacked. No edit to the report fixes it: the investigation goes back and measures again.
- **Important** — what was measured is described wrongly. Editing the report resolves it.

## Pass and report

The pass is `review-plan`'s **Pass**, run with this skill's target and lens list, and the fan-out sized per its **Dispatch**. Report per its **Report**, naming the skipped lenses and why.

Where `review-plan`'s **Pass** sends a verdict worker to **What counts as a finding**, the test it resolves to is this skill's own too, not `review-plan`'s: that skill's test asks whether the implementation that follows would stall, and no implementation follows a findings report — a Sweep completeness finding would be rejected for stopping nothing.

## Caller contract

This holds for every caller, rather than being defined at each call site.

- **One round is one pass plus the caller's fold-in.** This skill never re-reviews on its own; revising the report and re-running belong to the caller.
- **Two findings are the same** when a later pass faults the same claim on the same grounds, however the wording moved — including a claim restated after an edit meant to resolve it.
- **Stopping** is `using-dude`'s **Loop convergence**.
- **Nothing is published until the pass comes back clean.** Report each round to the caller in chat and never to GitHub, per `using-dude`'s **Stage boundaries**.
