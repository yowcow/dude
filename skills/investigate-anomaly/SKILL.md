---
name: investigate-anomaly
description: Use when root-causing an observed anomaly — production errors, an outage, a crashed job, an error-rate spike, unexplained cost or resource growth, or a metric drifting the wrong way — before any fix is proposed. Produces a blameless findings report, not a fix. Triggers on "why did this break", "root-cause this incident", "errors spiked", "costs keep growing", "this metric looks wrong", "what happened last night", "write the postmortem".
---

# Investigate Anomaly

Root-cause an observed anomaly. `superpowers:systematic-debugging` owns the core loop; this skill layers the anomaly-specific work on top of it: framing, evidence preservation, timeline reconstruction, change correlation, and blameless reporting.

## Investigation rules

- Preserve volatile evidence before anything else.
- Record each hypothesis with its test and verdict; refuted ones stay recorded, not retried.
- Exit when the root cause explains all observations — magnitude, timing, and scope included — or when the remaining unknowns are explicitly documented along with how to resolve them, distinguishing root cause from trigger and contributing factors.

## Rules

- Blameless: name systems and conditions, never people.
- Investigation is read-only: never mutate production state (restarts, config, data) without explicit user approval.

## Orchestration model

- Step 2 sources (logs, dashboards, queue/process state, usage exports) can be captured by one worker per source.
- Step 4 change classes are independent — fan out one worker per class; the orchestrator merges the results into the timeline.
- Hypothesis testing (Step 5) stays sequential in the orchestrator: each verdict informs the next hypothesis choice.

## Entry

An observed symptom and where it was observed: the error text or metric values, plus the log, dashboard, alert, or report that surfaced them. Closing any gap against the guidelines' **Understand** is Step 1's job — the first work here, not a precondition for starting.

## Explore

### Step 1: Frame the symptom

- Turn a vague concern ("costs keep growing", "something has felt off lately") into a measurable statement: what the guidelines' **Understand** asks an investigation to pin down, plus how large the deviation is against what baseline or expectation.
- If no number can be attached yet, producing one is the first evidence-gathering task — an anomaly that cannot be measured cannot be root-caused.

### Step 2: Capture and preserve

- Record the symptom as observed: exact error text/codes or metric values and their source, first and last occurrence, and current status (ongoing vs recovered).
- Snapshot anything that rotates or expires: logs, dashboards, queue depths, process state, billing/usage exports.

### Step 3: Reconstruct the timeline

- Use a single stated timezone.
- Anchor **last known good** and **first known bad**, then interleave symptoms with events.
- A gap you cannot narrow between last-good and first-bad is itself a finding — record it.

### Step 4: Correlate with changes

Sweep every change class across the last-good → first-bad window:

- deploys and rollbacks
- config and feature flags
- infrastructure changes
- dependency and upstream-service changes
- data shape or volume shifts; traffic pattern shifts
- scheduled jobs
- time-based expiries: certs, tokens, TTLs, quotas, disk filling
- pricing, plan, or quota changes (for cost anomalies)

## Validate

### Step 5: Test hypotheses

- Run the core loop per `superpowers:systematic-debugging`: the change classes swept in Step 4 are the hypothesis pool; the timeline is the evidence each hypothesis must fit.
- Distinguish **root cause** (the defect) from **trigger** (what activated it now) from **contributing factors** (what widened the blast radius).

## Synthesize

### Exit criteria

- The explanation meets **Investigation rules**' exit condition and accounts for the symptom's **shape** — a steady rate and a periodic spike of the same average are different symptoms; or
- the unknowns are documented with the monitoring or logging that would catch the next occurrence — a recovered anomaly leaves nothing to re-measure.

### Report format (blameless)

1. **Summary** — one paragraph.
2. **Impact** — who/what, duration, severity.
3. **Timeline**
4. **Root cause / Trigger / Contributing factors**
5. **Detection gaps** — why it wasn't caught sooner.
6. **Reproduction or observation baseline** — what makes the symptom observable again: the steps that reproduce it, or the window and metrics that show it.
7. **Remediation options** — immediate mitigation vs preventive fixes.
8. **Open questions**

**Reproduction or observation baseline** and **Remediation options** are what the guidelines' **Investigation → Change transition** hands to `plan-work` — that flow's input, not work this one starts.
