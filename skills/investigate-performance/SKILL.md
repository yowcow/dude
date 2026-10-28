---
name: investigate-performance
description: Use to investigate an observed performance shortfall — a slow endpoint, job, or query, or a latency, throughput, CPU, or memory metric that moved.
---

# Investigate Performance

- Root-cause an observed performance shortfall.
- Take `superpowers:systematic-debugging` as the owner of the core loop.
- Run none of its Phase 4 Implementation here, since an Investigation ends at findings.
- Layer only the performance-specific work on top of it.

## Rules

- Preserve volatile evidence before anything else.
- Record each hypothesis with its test and verdict.
- Leave refuted hypotheses recorded and never retried.
- Exit when the root cause explains all observations — magnitude, timing, and scope included; or
- Exit when the remaining unknowns are explicitly documented along with how to resolve them.
- Distinguish root cause from trigger and contributing factors.
- Measure before guessing: propose no fix without a number behind it.
- Account for variance, warm-up, and cold caches in the measurement itself before trusting a delta.
- Confirm you are measuring the thing you mean to (client-observed vs server-side time).

## Orchestration model

- Keep descending the layers (Step 3) sequential by design, since which layer to drill into depends on the previous measurement.
- Within a layer, independent measurements (CPU vs memory vs IO saturation) can each go to a worker.
- Have a measuring worker return the command it ran and its raw output.

## Entry

- Take an observed shortfall and where it was observed: the endpoint, job, or query that is slow, or the metric that moved, together with the measurement, trace, dashboard, or report it came from.
- Treat pinning down what falls short of `using-dude`'s **Understand** as the first task here rather than a precondition for starting, since Step 1 is where it happens.

## Explore

### Step 1: Frame and baseline

- Define the exact metric (p50/p99 latency, throughput, RSS, CPU%) and the target or prior value it is measured against.
- Fix the environment: hardware, dataset size, concurrency.
- Record the baseline numbers and the exact command that produced them.

### Step 2: Reproduce reliably

- Build a minimal reproduction with a realistic load shape.
- Where it only reproduces in production, define the observation window and metrics instead.
- Never load-test production without explicit user approval.

## Validate

### Step 3: Profile layer by layer

- Descend the layers, measuring each one's share of the total cost.
- Stop at the first layer that accounts for the shortfall before drilling in.

1. **System** — CPU/memory/disk/network saturation and errors (USE method); swapping, throttling, noisy neighbors.
2. **Runtime** — GC pressure and pause time; scheduler/thread/goroutine/process-pool saturation; connection pools. Use the language's native profiler.
3. **Application** — hot paths, repeated work in loops, per-request work that could be cached, lock contention, serialization cost, chatty external calls, retry amplification.
4. **Query/IO** — slow queries and their plans, missing indexes, N+1 patterns, round-trip counts, payload sizes.

## Synthesize

### Exit criteria

- A named bottleneck whose measured contribution explains the observed shortfall's magnitude — not just "found something slow"; or
- documented dead ends, each with the measurement that would settle it.

- Run `review-findings` on the report per its **Caller contract**.
- Publish per `using-dude`'s **Stage boundaries**.

### Report format

1. **Summary** — one paragraph.
2. **Numbers** — baseline vs observed vs target.
3. **Reproduction** — the minimal reproduction or the observation window, with the exact command behind the numbers.
4. **Root cause** — with the decisive measurement.
5. **Contributing factors**
6. **Fix options** — expected gain and cost of each.
7. **Open questions** — including documented dead ends, each with the measurement that would settle it.

- Carry **Reproduction** and **Fix options** forward through `using-dude`'s **Investigation → Change transition**, since they are the next flow's input and never work started from here.

## Escalation

- Take `using-dude`'s **Loop convergence** as this run's stopping conditions.
- Count one round as one core-loop measurement pass.
- Count a finding as repeating when a later pass faults the same layer for the same reason.
- Never re-diagnose evidence that invalidates the framed shortfall in place: stop and return to **Step 1** for re-framing.
