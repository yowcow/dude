---
name: review-plan
description: Use to review a planning artifact.
---

# Review Plan

Use on planning work before any code is written, or on a revision of it. This reviews the plan, not the code.

## Orchestration model

**This skill dispatches read-only reviewers; judging goes to `judge-findings`.** Everything else — gathering the inputs, sizing the fan-out, writing the report, and calling the pass clean — stays in the main loop.

- A reviewer takes its assigned lenses, reports findings, and hands back.
  - It never edits what it reviewed and never declares the plan clean.
  - It runs no project check: it reads the measurement record the dispatch hands it, per `using-dude`'s **Measurement records**, and where that record does not cover what it has to judge, it says what would have to be measured.
  - **Dispatch** sizes the fan-out.
  - Each reviewer goes out at the `high` tier in `using-dude`'s **Worker tier**.
  - A design flaw it doesn't report flows into the implementation, and every gate after this one reads the implementation, not the plan.
- **Judging a finding never happens in the main loop** either: it goes to `judge-findings`, and the orchestrator writes the report from the verdicts it returns and re-judges none of them.
- One invocation is one pass, and it never re-reviews on its own. Revising and re-running until it comes back clean belongs to the caller.

## What counts as a finding

One test admits everything this skill reports: **left as it is, would this make the implementation that follows stall or go wrong?** A gap that would send an implementer down the wrong path, leave them unable to proceed, or produce the wrong result is a finding. Nothing else is.

This test overrides the lenses. A lens names a failure mode to look for; naming one does not make every instance of it worth reporting. Terminology that drifts without misleading anyone, wording that could read better, a section a reviewer would have organised differently — these fail the test, so they are not findings, whatever lens surfaced them. Reviewer preference is never a finding here. Prose and formatting are findings only where they leave an implementer unable to tell what the plan means.

There is no non-blocking tier. A finding that passes the test has to be resolved before implementation; anything that fails it is left unsaid rather than recorded as a note. A gap in the measurement record's coverage is not such a note when the answer could change what the plan instructs: that is a finding against the plan line it leaves unsupported — the quoted line is its evidence — and `judge-findings` takes it to `needs-user` where it rests on a measurement. Only a gap whose answer cannot change what the plan instructs goes on the report's **not measured** line, saying what would have to be measured.

## Targets

One invocation reviews exactly one target, and **the caller declares which**. The target sets the lens list and the fan-out, because the two artifacts fail in different ways.

- **TODO list** — the design plus a numbered list of PR-sized items. Lenses: **Necessity, Completeness, Consistency, Reality, Risk**.
  - *Skip* **Assumptions** and **Executability**, and say so in the report: there is no task-level detail yet for either to bite on.
- **Implementation plan** — the detailed plan for one PR. Lenses: **Completeness, Consistency, Reality, Assumptions, Executability, Risk**.
  - *Skip* **Necessity**, and say so in the report: whether the work is warranted was settled when the TODO list was reviewed.
  - If this plan reaches past the scope boundary of the item it implements, that is not Necessity reopening — raise it under Consistency, against that item's stated completion criteria.
  - Completeness and Consistency here also cover error paths, migration and rollback, and ordering between tasks.

## Lenses

Each lens is a distinct failure mode, and none of them lowers the bar in **What counts as a finding**. Which ones apply comes from **Targets**; how many reviewers they map to comes from **Dispatch**.

- **Necessity** — whether the work is warranted at all: steps the request never asked for, scope the plan grew on its own, a smaller path to the same outcome, or an existing feature that already covers it. This lens reads the whole thing and questions that it should exist, not just how it reads.
- **Completeness** — requirements not covered; missing edge cases, error paths, migration, rollback, or docs.
  - On an **implementation plan**: also a task with no verification step.
  - On a **TODO list**: an item with no stated completion criteria.
  - **Not** a missing verification command — the TODO list is contractually forbidden to carry those, so flagging their absence would manufacture a finding against every item.
  - Verification detail is Executability's business, and Executability is skipped for this target.
- **Consistency** — steps that contradict each other, ordering or dependency errors, tasks assuming state no earlier task produces, terminology drift.
- **Reality** — mismatch with the repo as it is: existing failures, constraints, or config the plan ignores.
- **Assumptions** — what the plan takes for granted without checking: unstated preconditions, dependency behavior nobody verified, assumed environment, permissions, or data shape.
  - Where Reality catches what the repo contradicts, this catches what nobody has confirmed either way.
  - List each assumption and mark it verified or unverified.
- **Executability** — tasks too large or too vague to implement and verify independently.
  - Shared files that break task independence.
  - Verification that wouldn't actually show the change worked.
  - A named command whose result-testing method is unspecified counts here.
- **Risk** — blast radius, backward compatibility, data and security implications, and what happens if a task half-lands.
  - On a **TODO list**: also whether every intermediate state is safe — the PRs land one at a time, so a state where only some have merged has to hold together.

## Dispatch

Each reviewer gets its assigned lenses, the artifact under review, the original request, the paths it touches, and the measurement record's path when the caller has one covering what the plan would touch. Every reviewer takes the same stance: try to make the plan fail. One you cannot break passes — but a finding you cannot evidence is not a finding.

Size the fan-out to the target. Both targets here are small artifacts — a list of PR-sized items, or one PR's plan — so keep it small.

- **Default — one reviewer** takes the target's whole lens list.
- **Two reviewers**, when the work is large, risky, or spans subsystems.
  - Split the lens list into the ones that need only the artifact and the original request, and the ones that need to read the repo.
  - Independence is what the split buys — neither sees the other's findings, so neither anchors on them.

Use `superpowers:dispatching-parallel-agents` for the dispatch itself when there is more than one; this is independent fact-finding, not implementation. Don't restate its prompt-construction guidance here.

- On a revision — the caller hands over the record of an earlier pass — dispatch only the lenses that produced an accepted finding, plus Reality, since the artifact changed under it.
  - They review the edits that resolved those findings; that is the scope for every lens dispatched, Reality included.
  - An edit made for another reason that leaves what the plan instructs unchanged — a rewording, a tidy-up — is not part of that scope and does not earn a fresh look.
  - Pass the record along so rejected findings are not re-litigated.
  - Skip a lens only when it cannot apply, and say which and why.

## Finding contract

Each reviewer returns findings only — never a rewritten plan — with:

- **lens**, and **severity** — which says where the remedy lives, not how urgent it is.
  - **Critical**: the agreed design or approach is wrong, so no edit to the plan fixes it and the design needs approval again.
  - **Important**: the plan itself is wrong and editing it resolves this.
  - Both block implementation — **What counts as a finding** admits nothing that doesn't.
- **claim** — one sentence on what is wrong.
- **evidence** — `path:line` from the repo, or the quoted line from the artifact. No evidence, no finding.
- **suggested change** — what it should say instead.
- **not measured** — a separate line, not a finding: the question a lens could not judge because no measurement record covered it and no answer to it could change what the plan instructs, and what would have to be measured.

Report "no findings" explicitly rather than inventing one. Confine every search to the project root or narrower.

## Pass

1. Gather the inputs: the declared target, the artifact, the original request, the paths it touches, the measurement record's path when the caller has one covering what the plan would touch, and the record of an earlier pass if the caller supplied one.
2. Dispatch reviewers, sized per **Dispatch**.
3. Hand the reviewers' findings to `judge-findings`, and take back its verdicts, with the measurement record's path when one was handed to the reviewers.
   - The target it judges against is the plan and the repo, the requirements are the original request, and the earlier rounds are the caller's record.
   - The caller's acceptance criteria are **What counts as a finding**.
4. Report per **Report**, and stop there — revising and re-reviewing are the caller's job.

This pass is clean per `using-dude`'s **Loop convergence** loop-clean when no finding survives step 3. A `needs-user` survives it: the pass ends non-clean and that finding goes to a person, with the meaning `judge-findings`'s **Verdicts** gives `needs-user` — here no edit to the plan settles it. Another pass is the obvious alternative and it is the wrong one: **Dispatch**'s revision rule scopes every lens it sends out, Reality included, to the edits that resolved an accepted finding, and a `needs-user` produced none, so the re-run comes back clean over a question nobody answered. What the person settles comes back as an ordinary revision: the caller's record carries that finding among the accepted and fixed, so **Dispatch** sends its lens out again, scoped to the edit the answer produced.

## Report

Report to the caller in chat, never to GitHub, per `using-dude`'s **Stage boundaries**. Report, for this pass:

- the target reviewed, the fan-out used, and any lens skipped with why
- accepted findings with lens, severity, evidence, and suggested change
- rejected findings with the reason
- `needs-user` findings, with why the worker put the decision to a person
- the **not measured** lines, each with what would settle it
- the verdict: clean, or the blocking findings that remain — flagging any Critical finding separately, since **Finding contract** puts its remedy outside a plan edit
