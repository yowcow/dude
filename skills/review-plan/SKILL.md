---
name: review-plan
description: Use to review a planning artifact.
---

# Review Plan

Use on planning work before code, or on its revision. This reviews the plan, not the code.

## Orchestration model

**Dispatch read-only reviewers; judging goes to `judge-findings`.** Everything else — gathering inputs, sizing fan-out, writing the report, calling the pass clean — stays in the main loop.

A reviewer reports findings and hands back. It never edits, never declares clean, runs no project check. **Dispatch** sizes the fan-out. Each reviewer goes out at the `high` tier in `using-dude`'s **Worker tier**: a missed design flaw flows into implementation, and every later gate reads the implementation, not the plan.

**Judging never happens in the main loop** either: the orchestrator writes the report from `judge-findings` verdicts and re-judges none. One invocation is one pass and never re-reviews on its own. Revising and re-running belong to the caller.

## What counts as a finding

One test admits everything: **left as it is, would this make the implementation stall or go wrong?** A gap sending an implementer down the wrong path, leaving them stuck, or producing the wrong result is a finding. Nothing else is.

This overrides the lenses. Drifting terminology that misleads nobody, better wording, a differently organised section — never findings. Reviewer preference is never a finding. Prose and formatting count only where the implementer cannot tell what the plan means.

No non-blocking tier: a passing finding must resolve before implementation; anything failing it goes unsaid, never recorded as a note. A question no lens can judge without a measurement is a finding against the plan line it leaves unsupported — quoted as its evidence — when the answer could change what the plan instructs; `judge-findings` takes it to `needs-user` there. Only a question whose answer cannot change the plan goes on the **not measured** line with what would settle it.

## Targets

One invocation reviews exactly one target, and **the caller declares which**. The target sets lenses and fan-out.

- **TODO list** — the design plus numbered PR-sized items. Lenses: **Necessity, Completeness, Consistency, Reality, Risk**.
  - *Skip* **Assumptions** and **Executability**: no task detail yet for either to bite on.
- **Implementation plan** — one PR's detail. Lenses: **Completeness, Consistency, Reality, Assumptions, Executability, Risk**.
  - *Skip* **Necessity**: settled when the TODO list was reviewed.
  - Past-scope detail is not Necessity reopening: raise it under Consistency against the item's completion criteria.
  - Completeness and Consistency also cover error paths, migration and rollback, and ordering.

## Lenses

Each is a failure mode; none lowers the bar above. **Targets** selects which apply; **Dispatch** selects how many reviewers.

- **Necessity** — is the work warranted: unrequested steps, grown scope, a smaller path, an existing feature covering it.
- **Completeness** — uncovered requirements; missing edges, error paths, migration, rollback, docs.
  - Implementation plan: also a task with no verification step.
  - TODO list: also an item with no completion criteria.
  - Never a missing verification command on a TODO list: contractually forbidden there, so flagging it manufactures a finding per item.
- **Consistency** — contradicting steps, ordering or dependency errors, state no earlier task produces, drifting terms.
- **Reality** — mismatch with the repo: ignored failures, constraints, config.
- **Assumptions** — unchecked preconditions, unverified dependency behaviour, assumed environment, permissions, data shape. List each, marked verified or unverified.
- **Executability** — tasks too large or vague to implement and verify alone; shared files breaking independence; verification that would not show the change; a named command with unspecified result-testing.
- **Risk** — blast radius, compatibility, data and security, half-landed state. On a TODO list: also whether every intermediate state holds with only some PRs merged.

## Dispatch

Each reviewer gets its lenses, the artifact, the original request, and the paths it touches. Stance: try to make the plan fail. One that will not break passes — but an unevidenced finding is not a finding.

Keep it small: both targets are small.

- **Default — one reviewer** takes the whole lens list.
- **Two reviewers** when large, risky, or spanning subsystems: split artifact-only lenses from repo-reading ones. The split buys independence.

Use `superpowers:dispatching-parallel-agents` when dispatching more than one; this is fact-finding, not implementation.

On a revision — the caller hands the earlier pass record — dispatch only lenses that produced an accepted finding, plus Reality. Scope is the resolving edits; a rewording that changes no instruction earns no fresh look. Pass the record so rejected findings are not re-litigated. Skip a lens only when inapplicable, saying which and why.

## Finding contract

Findings only — never a rewritten plan — each with:

- **lens**, and **severity** — where the remedy lives. **Critical**: the design is wrong, no plan edit fixes it, needs re-approval. **Important**: the plan is wrong, an edit fixes it. Both block implementation.
- **claim** — one sentence on what is wrong
- **evidence** — `path:line` or the quoted artifact line. No evidence, no finding
- **suggested change** — what it should say instead
- **not measured** — a question no lens could judge that changes nothing the plan instructs, plus what would settle it

Report "no findings" explicitly. Confine every search to the project root or narrower.

## Pass

1. Gather the declared target, the artifact, the original request, the paths, and any earlier pass record.
2. Dispatch reviewers per **Dispatch**.
3. Hand findings to `judge-findings` and take back verdicts. It judges the plan and repo against the original request, under **What counts as a finding**. A measurement-route `needs-user` is settled before the person route: the caller takes that one bounded measurement, records it, and hands the finding back; this pass runs no project check. Only what the caller may not spend goes to a person.
4. Report per **Report** and stop. Revising and re-reviewing are the caller's.

Clean per `using-dude`'s **Loop convergence** loop-clean is no surviving finding. A `needs-user` survives it and takes its route: measurement-route findings come back with the record for re-judging; person-route findings go to a person, and no plan edit settles them first. Never re-run to clear a `needs-user`: **Dispatch** scopes every lens to resolving edits, and a `needs-user` produced none, so the re-run returns clean over an unanswered question. A settled answer returns as an ordinary revision with that finding carried accepted-and-fixed.

## Report

Report to the caller in chat, never to GitHub, per `using-dude`'s **Stage boundaries**: the target, the fan-out, lenses skipped with why, accepted findings with lens, severity, evidence, and suggested change, rejected findings with reasons, `needs-user` findings with routes, **not measured** lines, and the verdict — clean or the blocking findings left, flagging any Critical separately.
