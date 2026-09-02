---
name: simplify-code
description: Use after implementation and before code review or PR creation to simplify recently modified code while preserving behavior. Triggers on "simplify this", "clean up the diff", "run a code-simplifier pass", "tidy this up before review".
---

# Simplify Code

Use after code changes and before `review-code`.

It is kept local rather than delegated: ready-made simplifiers draw no boundary against optimizations whose justification needs a measurement, and each is confined to a single assistant, so none can carry a pass that installs to all of them.

One invocation is one simplification pass, and the pass owns its apply-verify loop: propose, apply, run the checks, propose again, until nothing actionable is left. Re-entry is not part of it — that belongs to the caller, on the same terms as `review-code`.

## Orchestration model

**This skill dispatches proposers: read-only workers that may run in parallel.** Everything else runs in the main loop.

- The orchestrator owns this pass: it dispatches proposers, judges what they return, applies the accepted proposals, verifies, and reports. It decides when nothing actionable remains — a proposer never does.
- Proposers are read-only workers, following the contract stated in `review-code`'s **Orchestration model** and bought for the same reason. Each gets the diff, the paths it touches, and its assigned lenses. A proposer returns proposals only — never an edited file, never a run of the project's checks, and never a verdict that the pass is clean.
- Proposers stay read-only for two reasons beyond that contract: it matches how the other local skills treat workers (`pr-to-ready` keeps every code change, commit, and push in the orchestrator), and `superpowers:verification-before-completion` makes the orchestrator re-verify a worker's claims anyway — so letting a worker apply and self-verify buys nothing.

## Scope

- Resolve scope the way `review-code`'s **Scope** does, rather than a second time here: the two skills run on the same code in the same pass of `implement-work`'s completion gate, so a separate ladder in this file would be a second answer — and on a stacked branch the wrong one, since only that ladder reads back what the branch was cut from. Don't broaden cleanup unless the user asks.
- If a worthwhile simplification needs files outside the diff, report it instead of changing it.
- Preserve behavior exactly: outputs, public APIs, data migrations, test intent, and user-visible semantics.
- When the existing checks can't prove a simplification behavior-preserving, add the minimal characterization test that can, and say so in the report. That's the proof, not scope creep.

## Lenses

Each lens is a distinct kind of avoidable complexity, and every one is behavior-preserving. How many proposers they map to is decided in **Dispatch** below.

- **Structure** — unnecessary complexity, nesting, or branching; redundant or duplicated logic; unclear names; related logic that could be consolidated.
- **Cost** — work the change itself added beyond what its result needs, where the excess is evident from reading the diff rather than from a measurement: per-iteration queries or IO that one call covers. Reshape to the same result at the lower cost.
- **Noise** — formatting churn unrelated to the task; comments that merely restate the code.
- **Reuse** — places where the diff reimplements what the repository already has. Grep the shared and utility modules and the files adjacent to the change, and name the existing helper it should call instead.

## Don't over-simplify

- No clever one-liners or dense expressions just to cut lines; no nested ternaries for multi-branch logic (prefer `if`/`else` or `switch`).
- Keep helpful abstractions and separation of concerns; don't merge unrelated concerns into one unit.
- Don't make code harder to debug, extend, or review.
- Don't optimize speculatively: anything whose justification needs a measurement — a different algorithm for scale, caching, concurrency, precomputed indexes — is out of scope. Report it and leave it to `investigate-performance`. Repairing cost the diff itself introduced is not speculative, and the baseline decides which it is: restoring the cost the code had before the change is in scope, making it cheaper than it has ever been is not.

## Dispatch

Proposers are read-only and share no mutable state, so they may run in parallel (`superpowers:dispatching-parallel-agents` — this is independent fact-finding, not implementation). The fan-out is sized to the diff:

- **Default** — one proposer takes every lens.
- **Large diff, or one spanning subsystems** — one proposer per lens, dispatched together.

Dispatch a fresh proposer each round and give it the diff as it now stands, not the previous round's proposals — a proposer shown what was just applied anchors on it. Inline **Scope**, **Lenses**, and **Don't over-simplify** into the prompt so the proposer doesn't go hunting for them, and confine its searches to the project root or narrower.

## Proposal contract

Each proposer returns proposals only — never an edited file — with:

- **location** — `path:line` within the diff, numbered as the file now stands.
- **lens**.
- **change** — what the code should say instead.
- **behavior preservation** — why the change cannot alter behavior, and which existing check would catch it if it did. When no existing check can prove it, propose the minimal characterization test that would, per **Scope**.

Report "no proposals" explicitly rather than inventing one.

## Pass

1. Gather the inputs: the diff and the paths it touches.
2. Dispatch proposers against the diff, sized per **Dispatch**.
3. Evaluate every proposal with `superpowers:receiving-code-review`: reject — with a stated reason — anything that changes behavior, that needs a measurement to justify it (see **Don't over-simplify**), that reaches outside the diff (see **Scope**), or that only reflects proposer preference.
4. Apply the accepted proposals yourself, then run the checks the project defines — in its README, Makefile targets, package scripts, or CI config — and read their actual output.
5. Loop back to step 2 with a fresh proposer while actionable simplification remains, subject to **Convergence**.
6. Report per **Report**.

## Convergence

This pass's loop stops per `using-dude`'s **Loop convergence**. A round here is one dispatch → judge → apply → verify cycle, and two proposals are the same finding when they target the same location with the same change, however the wording moved — including one re-raised after it was rejected.

## Report

- the fan-out used
- what changed, and what behavior was preserved
- proposals rejected, with the reason
- the checks that ran, and what they actually printed
- any simplification left undone, including anything reported instead of changed
