# Measurement records

This file holds the rationale and the full roster. The rule body is `using-dude`'s **Measurement records** and is not repeated here.

## Why the measurement record lives outside the work tree

A measurement record's body sits under the worktree's git dir — `.git/worktrees/<name>` for a linked worktree — beside the completion gate's tree records. Nothing there is ever committed, nothing there is a working-tree change, and each worktree keeps its own body independently. The consumed project's ignore file is never touched, so no repository needs a new entry.

## Why not a cache shared across sessions or worktrees

The duplication measured on 2026-10-22 was inside one session, where four workers re-derived one baseline. Sharing measurement records across sessions or worktrees leaves two questions unresolved: who updates a measurement record, and when it has become stale. It also adds a new failure path with no measured duplicate to justify it. A cross-session duplicate, once measured, gets its own issue and its own answer.

## Why not a script

A missing field would be machine-checkable. Whether a measurement record still covers the question a worker is asked is not: that stays the orchestrator's judgment, so a script would enforce only the envelope and leave the expensive question untouched. AUTHORING's generic-operation rule keeps this prose, with nothing new to maintain.

## The roster

The target class is a skill whose judgment can rest on a measurement a read-only worker would otherwise re-derive: it dispatches such workers, produces the measurement as its own deliverable, or is an entry whose own dispatch carries a measurement record. No skill in this table hands raw measurement data across its work today and none sets a bound on re-measuring. The Reason column records the applicability decision and the gap as this PR's tree stands; the producer, worker-contract, entry, and measurement-deliverable changes that close a gap are later issues and are out of scope here.

| Skill | Applicability | Reason |
| --- | --- | --- |
| `using-dude` | does not apply | Owns the rule (**Measurement records**); it dispatches nothing, so it carries no measurement of its own. |
| `implement-work` | applies | Producer, not wired here: **Isolation** establishes a verified baseline and keeps no measurement record of it; the later producer change makes that baseline a measurement record and carries its path into its dispatches. |
| `propose-alternatives` | applies | Worker contract: the worker may measure and is handed no measurement record; the later worker-contract change reads a measurement record first and bounds the worker's own measurement to one. |
| `review-plan` | applies | Read-only reviewers run no check under no rule today and are handed no measurement record; the later worker-contract change adds the ban and pairs it with reading the measurement record. |
| `judge-findings` | applies | Judging workers edit nothing and are handed no measurement record; the later worker-contract change bans executing checks and pairs that ban with reading the measurement record. |
| `vet-code` | applies | The reviewer is not to execute checks and is handed no measurement record; the later worker-contract change pairs that ban with reading the measurement record, which may sit outside its read-root. |
| `simplify-code` | applies | Its workers are under the existing no-execution rule and are handed no measurement record; the later worker-contract change pairs that ban with reading the measurement record. |
| `review-findings` | applies | Sweep completeness judges from the trace the report left and has no measurement record beside it; the later change adds the measurement record to that trace rather than a re-run. |
| `audit-code` | applies | The measurement is the deliverable: the sweep's raw output is the evidence a later reader re-reads rather than re-runs; the later change keeps that raw output as a measurement record and puts its path in the report. |
| `investigate-performance` | applies | The measurement is the deliverable: timing and profiling are the explanation's evidence and must stay reproducible; the later change keeps them in a measurement record and cites its path in the report. |
| `investigate-anomaly` | applies | The measurement is the deliverable: the observed change is established by measurement the report cites; the later change keeps that measurement as a measurement record and puts its path in the report. |
| `settle-question` | applies | The measurement is the deliverable: the judgment rests on measured facts that stay checkable; the later change makes the report's measurement base a measurement record with its path. |
| `pr-to-ready` | applies | Entry with a diagnostic worker: a failed check's cause is diagnosed by a read-only worker that would otherwise re-measure; the later entry change has that worker return the command and raw output and the orchestrator record them. |
| `plan-work` | does not apply | Entry: it dispatches no worker of its own and follows the contracts of the skills it calls; a measurement record's path only passes through. |
| `review-code` | applies | Entry: it dispatches no worker of its own, but its step 5 verification runs the project's checks on the tree its own fixes changed — a measurement no earlier record still covers and the round-2 reviewer is forbidden to re-derive. The later entry change records that command and raw output and hands its path to `vet-code` with the earlier rounds' record. |
| `review-pr` | does not apply | Entry: the same, with no worker and no measurement of its own. |
