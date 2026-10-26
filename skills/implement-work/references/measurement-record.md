# Measurement records

This file holds the rationale and the full roster. The rule body is `using-dude`'s **Measurement records** and is not repeated here.

## Why the measurement record lives outside the work tree

A measurement record's body sits under the worktree's git dir — `.git/worktrees/<name>` for a linked worktree — beside the completion gate's tree records. Nothing there is ever committed, nothing there is a working-tree change, and each worktree keeps its own body independently. The consumed project's ignore file is never touched, so no repository needs a new entry.

## Why not a cache shared across sessions or worktrees

The duplication measured on 2026-10-22 was inside one session, where four workers re-derived one baseline. Sharing measurement records across sessions or worktrees leaves two questions unresolved: who updates a measurement record, and when it has become stale. It also adds a new failure path with no measured duplicate to justify it. A cross-session duplicate, once measured, gets its own issue and its own answer.

## Why not a script

A missing field would be machine-checkable. Whether a measurement record still covers the question a worker is asked is not: that stays the orchestrator's judgment, so a script would enforce only the envelope and leave the expensive question untouched. AUTHORING's generic-operation rule keeps this prose, with nothing new to maintain.

## Judge input and verdict records

The completion gate keeps the judge handoff outside the tree, in `dude-measurements/implement-work/`: `judge-input-<round>.md` holds what the caller handed `judge-findings`, and `judge-verdict-<round>.md` holds what `judge-findings` returned, recorded whole and unreworded. Without the pair a later check cannot tell a dropped input from a judgment. Rounds after handoff continue the gate's numbering in that same dir; standalone `review-code` identity stays out of scope here.

The input file carries the scope and requirements whole as `vet-code` handed them, plus every Issues finding whole, every Declined to judge line verbatim, the earlier rounds' record, the measurement record's path or, where no record covers, that there is none and what is missing, the acceptance criteria text, and the round number. A line missing there reads as an incomplete record, never as a judgment, because the file is the handoff. The verdict file carries each item as given with its verdict — each `accept` with its fix, value, and reason — and the input file's name. Rewording a fix there silently turns a `record` accept into a fix. Both files carry the commit and the tree hash for the judged tree per **Subject identity**: the commit the workspace is on and the working-tree hash the covering `record-tree.sh` call printed, copied from that phase's `dude-completion-gate/` record with the phase named, never a new invocation for the judge files. With no items there is no judge worker and no verdict file, but the caller still writes the empty input file with that identity and empty item lists, so a later check reads "nothing to cover" rather than "record missing".

The wire shape is fixed: the input envelope names `Round:`, `Commit:`, and `Tree:`, then one `Finding: <text>` or `Candidate: <text>` line per item, each byte-exact; the verdict envelope names `Round:`, `Input: judge-input-<R>.md`, `Commit:`, and `Tree:`, then one block per item — the item line byte-exact, `Verdict: accept`, `reject`, or `needs-user` on the first line, and for `accept` `Value: apply` or `record` on the second. The writer emits exactly this; anything else shaped is malformed, never a judgment. That copy-from-the-phase-record and never-a-new-invocation identity discipline is the completion gate's; a Step-1 pair back-patches only each input file envelope's `Commit:` and `Tree:` lines to the post-commit tree after the caller commits, leaving the body byte-identical (verdict files' echo is unread and left as written), and carries its Step-1 origin — the post-commit HEAD and tree with the phase name — as an `Origin:` envelope line (named keys only are read, so the line is inert to the checker).

## The roster

The target class is a skill whose judgment can rest on a measurement a read-only worker would otherwise re-derive: it dispatches such workers, produces the measurement as its own deliverable, or is an entry whose own dispatch carries a measurement record. The Reason column records the applicability decision and the gap as this PR's tree stands; the worker-contract, entry, and measurement-deliverable changes that close a gap are later issues and are out of scope here.

| Skill | Applicability | Reason |
| --- | --- | --- |
| `using-dude` | does not apply | Owns the rule (**Measurement records**); it dispatches nothing, so it carries no measurement of its own. |
| `implement-work` | applies | **Isolation**'s verified baseline is a measurement record, and the completion gate's Verify run and its Simplify run, where it ran one, are records; each is handed on only to a dispatch whose subject it still matches. |
| `propose-alternatives` | applies | Worker contract: the worker may measure and is handed no measurement record; the later worker-contract change reads a measurement record first and bounds the worker's own measurement to one. |
| `review-plan` | applies | Read-only reviewers run no check under no rule today and are handed no measurement record; the later worker-contract change adds the ban and pairs it with reading the measurement record. |
| `judge-findings` | applies | Judging workers edit nothing and are handed no measurement record; the later worker-contract change bans executing checks and pairs that ban with reading the measurement record. |
| `vet-code` | applies | The reviewer is not to execute checks and is handed no measurement record; the later worker-contract change pairs that ban with reading the measurement record, which may sit outside its read-root. |
| `simplify-code` | applies | Its workers are under the existing no-execution rule and are handed no measurement record; its main loop runs the project's checks when it applies a proposal, and the completion gate records this skill's own check run, where it ran one, as `simplify-<round>.md` and hands it the `verify-<round>.md` record as the caller's covering result; the later worker-contract change pairs that ban with reading the measurement record. |
| `review-findings` | applies | Sweep completeness judges from the trace the report left and has no measurement record beside it; the later change adds the measurement record to that trace rather than a re-run. |
| `audit-code` | applies | The measurement is the deliverable: the sweep's raw output is the evidence the reviewer in the same run re-reads rather than re-runs; the later change keeps that raw output as a measurement record and cites its path in the report beside the observation and the `path:line` each finding rests on, never in place of them. |
| `investigate-performance` | applies | The measurement is the deliverable: timing and profiling are the explanation's evidence and must stay reproducible; the later change keeps them in a measurement record and cites its path in the report beside the baseline and observed numbers and the reproduction command, never in place of them. |
| `investigate-anomaly` | applies | The measurement is the deliverable: the observed change is established by measurement the report cites; the later change keeps that measurement as a measurement record and puts its path in the report beside the measurement the timeline and root cause rest on, never in place of it. |
| `settle-question` | applies | The measurement is the deliverable: the judgment rests on measured facts that stay checkable; the later change keeps the report's measurement base as the measured revision, tree, or record, and cites the measurement record's path beside it, never in place of it, since the record sits in the producer worktree's git dir and a later reader of the published report cannot read that path. |
| `pr-to-ready` | applies | Entry with a diagnostic worker: a failed check's cause is diagnosed by a read-only worker that would otherwise re-measure; the later entry change has that worker return the command and raw output and the orchestrator record them. |
| `plan-work` | does not apply | Entry: it dispatches no worker of its own and follows the contracts of the skills it calls; a measurement record's path only passes through. |
| `review-code` | applies | Entry: it dispatches no worker of its own, but its step 5 verification runs the project's checks on the tree its own fixes changed, or consumes the caller's covering result — the completion gate's record covering that tree, or the judged claims table in **Review**'s doc-only case. Where its own fixes moved the tree, that run is a measurement no record covers and the round-2 reviewer is forbidden to re-derive. The later entry change records that command and raw output and hands its path to `vet-code` with the earlier rounds' record. |
| `review-pr` | does not apply | Entry: the same, with no worker and no measurement of its own. |
