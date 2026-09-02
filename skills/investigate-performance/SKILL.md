---
name: investigate-performance
description: Use when diagnosing an observed performance shortfall — a slow endpoint, job, or query, a latency/throughput regression, or CPU/memory growth — to root-cause it with measurements before any fix is proposed. Produces a findings report, not a fix. Triggers on "why is this slow", "latency spiked", "perf regression", "high CPU", "memory keeps growing", "find the bottleneck".
---

# Investigate Performance

Root-cause an observed performance shortfall. `superpowers:systematic-debugging` is the core loop and runs unchanged here. This skill adds only the performance-specific layers on top: what to measure, in what order, and how to report.

## Investigation rules

- Preserve volatile evidence before anything else.
- Record each hypothesis with its test and verdict; refuted ones stay recorded, not retried.
- Exit when the root cause explains all observations — magnitude, timing, and scope included — or when the remaining unknowns are explicitly documented along with how to resolve them, distinguishing root cause from trigger and contributing factors.

## Rules

- Measure before guessing: no fix proposal without a number behind it.
- Account for variance, warm-up, and cold caches in the measurement itself before trusting a delta — and confirm you are measuring the thing you mean to (client-observed vs server-side time).

## Orchestration model

- Descending the layers (Step 3) stays sequential by design — which layer to drill into depends on the previous measurement.
- Within a layer, independent measurements (CPU vs memory vs IO saturation) can each go to a worker.

## Entry

An observed shortfall and where it was observed: the endpoint, job, or query that is slow, or the metric that moved, together with the measurement, trace, dashboard, or report it came from. Where that falls short of what `using-dude`'s **Understand** asks for, pinning it down is the first task here rather than a precondition for starting — Step 1 is where it happens.

## Explore

### Step 1: Frame and baseline

- Define the exact metric (p50/p99 latency, throughput, RSS, CPU%) and the target or prior value it is measured against.
- Fix the environment: hardware, dataset size, concurrency.
- Record the baseline numbers and the exact command that produced them.

### Step 2: Reproduce reliably

- Build a minimal reproduction with a realistic load shape.
- If it only reproduces in production, define the observation window and metrics instead — never load-test production without explicit user approval.

## Validate

### Step 3: Profile layer by layer

Descend the layers, measuring each one's share of the total cost; stop at the first layer that accounts for the shortfall before drilling in.

1. **System** — CPU/memory/disk/network saturation and errors (USE method); swapping, throttling, noisy neighbors.
2. **Runtime** — GC pressure and pause time; scheduler/thread/goroutine/process-pool saturation; connection pools. Use the language's native profiler (e.g. pprof, NYTProf, Xdebug/Blackfire, fprof/recon, `--cpu-prof`).
3. **Application** — hot paths, repeated work in loops, per-request work that could be cached, lock contention, serialization cost, chatty external calls, retry amplification.
4. **Query/IO** — slow queries and their plans, missing indexes, N+1 patterns, round-trip counts, payload sizes.

## Synthesize

### Exit criteria

- A named bottleneck whose measured contribution explains the observed shortfall's magnitude — not just "found something slow"; or
- documented dead ends, each with the measurement that would settle it.

### Report format

1. **Summary** — one paragraph.
2. **Numbers** — baseline vs observed vs target.
3. **Reproduction** — the minimal reproduction or the observation window, with the exact command behind the numbers.
4. **Root cause** — with the decisive measurement.
5. **Contributing factors**
6. **Fix options** — expected gain and cost of each.
7. **Open questions**

What a fix carries into `plan-work` is **Reproduction** and **Fix options**, per `using-dude`'s **Investigation → Change transition** — input to that flow, never work started from here.
