---
name: investigate-anomaly
description: Use to investigate an observed anomaly — a failure, an incident, or an unexplained metric or cost change other than a performance shortfall.
---

# Investigate Anomaly

- Root-cause an observed anomaly.
- Take `superpowers:systematic-debugging` as the owner of the core loop.
- Run none of its Phase 4 Implementation here, since an Investigation ends at findings.
- Layer only the anomaly-specific work on top of it: framing, evidence preservation, timeline reconstruction, change correlation, and blameless reporting.

## Rules

- Record each hypothesis with its test and verdict.
- Leave refuted hypotheses recorded and never retried.
- Exit when the root cause explains all observations — magnitude, timing, and scope included; or
- Exit when the remaining unknowns are explicitly documented along with how to resolve them.
- Distinguish root cause from trigger and contributing factors.
- Stay blameless: name systems and conditions, never people.
- Keep the investigation read-only: never mutate production state (restarts, config, data) without explicit user approval.

## Orchestration model

- Step 2 sources (logs, dashboards, queue/process state, usage exports) can be captured by one worker per source.
- Have a capturing or sweeping worker return the command it ran and its raw output.
- For a capture or sweep that ran no command, have it return its source, window, and the export, snapshot, or records it read.
- Fan out one worker per Step 4 change class, since the classes are independent.
- Merge the results into the timeline in the orchestrator.
- Keep hypothesis testing (Step 5) sequential in the orchestrator, since each verdict informs the next hypothesis choice.

## Entry

- Take an observed symptom and where it was observed: the error text or metric values, plus the log, dashboard, alert, or report that surfaced them.
- Treat closing any gap against `using-dude`'s **Understand** as Step 1's job, since it is the first work here rather than a precondition for starting.

## Explore

### Step 1: Frame the symptom

- Turn a vague concern into a measurable statement: what `using-dude`'s **Understand** asks an investigation to pin down, plus how large the deviation is against what baseline or expectation.
- Where no number can be attached yet, make producing one the first evidence-gathering task, since an anomaly that cannot be measured cannot be root-caused.

### Step 2: Capture and preserve

- Record the symptom as observed: exact error text/codes or metric values and their source, first and last occurrence, and current status (ongoing vs recovered).
- Snapshot anything that rotates or expires: logs, dashboards, queue depths, process state, billing/usage exports.

### Step 3: Reconstruct the timeline

- Use a single stated timezone.
- Anchor **last known good** and **first known bad**, then interleave symptoms with events.
- Treat a gap you cannot narrow between last-good and first-bad as itself a finding and record it.

### Step 4: Correlate with changes

- Sweep every change class across the last-good → first-bad window:

- deploys and rollbacks
- config and feature flags
- infrastructure changes
- dependency and upstream-service changes
- data shape or volume shifts
- traffic pattern shifts
- scheduled jobs
- time-based expiries: certs, tokens, TTLs, quotas, disk filling
- pricing, plan, or quota changes (for cost anomalies)

## Validate

### Step 5: Test hypotheses

- Run the core loop per `superpowers:systematic-debugging`: the change classes swept in Step 4 are the hypothesis pool, and the timeline is the evidence each hypothesis must fit.
- Distinguish **root cause** (the defect) from **trigger** (what activated it now) from **contributing factors** (what widened the blast radius).

## Synthesize

### Exit criteria

- The explanation meets **Rules**' exit condition and accounts for the symptom's **shape** — a steady rate and a periodic spike of the same average are different symptoms; or
- the unknowns are documented with the monitoring or logging that would catch the next occurrence.

- Run `review-findings` on the report per its **Caller contract**.
- Publish per `using-dude`'s **Stage boundaries**.

### Report format (blameless)

1. **Summary** — one paragraph.
2. **Impact** — who/what, duration, severity.
3. **Timeline**
4. **Root cause / Trigger / Contributing factors**
5. **Detection gaps** — why it wasn't caught sooner.
6. **Reproduction or observation baseline** — what makes the symptom observable again: the steps that reproduce it, or the window and metrics that show it.
7. **Remediation options** — immediate mitigation vs preventive fixes.
8. **Open questions**

- Carry **Reproduction or observation baseline** and **Remediation options** forward through `using-dude`'s **Investigation → Change transition**, since they are the next flow's input and not work this one starts.

## Escalation

- Take `using-dude`'s **Loop convergence** as this run's stopping conditions.
- Count one round as one core-loop hypothesis test.
- Count a finding as repeating when a later pass faults the same hypothesis for the same reason.
- Never re-diagnose evidence that invalidates the framed symptom in place: stop and return to **Step 1** for re-framing.
