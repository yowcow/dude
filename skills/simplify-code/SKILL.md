---
name: simplify-code
description: Use to simplify recently modified code and human-facing docs while preserving behavior and stated facts.
---

# Simplify Code

It is kept local rather than delegated: ready-made simplifiers draw no boundary against optimizations whose justification needs a measurement, and each is confined to a single assistant, so none can carry a pass that installs to all of them.

One invocation is one simplification pass, and the pass owns its apply-verify loop: propose, apply, run the checks, propose again, until nothing actionable is left. Re-entry is not part of it — that belongs to the caller: this pass never re-enters on its own; re-running after something else changed the code or a doc in scope is the caller's.

## Orchestration model

**This skill dispatches one kind of read-only worker, proposers; judging goes to `judge-findings`.** Everything else runs in the main loop.

- The orchestrator owns this pass: it dispatches the proposers, hands their proposals to `judge-findings`, applies the accepted proposals, verifies, and reports. It decides when nothing actionable remains — a proposer never does.
- Proposers are read-only workers: each gets the diff, the paths it touches, and its assigned lenses, and returns proposals only — never an edited file, never a run of the project's checks, and never a verdict that the pass is clean — at the `high` tier in `using-dude`'s **Worker tier**. What that buys is a fresh context unanchored on why the code ended up this way; a proposal it doesn't return reads as nothing actionable.
- Proposers stay read-only for one reason beyond that contract: `superpowers:verification-before-completion` makes the orchestrator re-verify a worker's claims anyway — so letting a worker apply and self-verify buys nothing.

## Scope

Resolve what to simplify in this order, and declare the resolved scope before dispatching anything:

1. **Caller-supplied** — a SHA range or paths. Use it as given.
2. **Uncommitted changes present** — the working tree diff: staged, unstaged, and untracked files.
3. **Clean tree** — the commits ahead of the base the caller names; on a direct invocation, ask the user for the range instead of guessing it.
4. **Nothing to simplify** — no uncommitted change, and no range with anything in it. Ask the user what to simplify. Never widen to the whole repository on a guess.

Kept as a second copy so this pass resolves the same scope without borrowing: the caller hands it the same range the review runs on.

**Docs are in scope by role, not by path.** Human-facing docs — prose a person reads to install, operate, or understand the project, such as a README, a guide, usage docs, or explanatory text under `docs/` — are part of what this pass simplifies when the diff touches them. Agent-facing text, which selects or constrains an agent's behavior — `SKILL.md`, `AGENTS.md`, `CLAUDE.md`, agent instructions, and the plans or design records an agent reads — is out of scope, as are structured records such as changelogs and licences and anything generated or vendored. Judge by what the text does, and when the role is unclear leave it out. Code comments are not docs here; a comment that only restates the code belongs to **Noise**.

- Don't broaden cleanup unless the user asks.
- If a worthwhile simplification needs files outside the diff, report it instead of changing it.
- Preserve code behavior exactly: outputs, public APIs, data migrations, test intent, and user-visible semantics. A human-facing doc keeps its facts instead, per **Proposal contract**'s claims table.
- When the existing checks can't prove a code simplification behavior-preserving, add the minimal characterization test that can, and say so in the report. That's the proof, not scope creep. A doc change gets no test: its proof is the judged claims table, and no check stands in for it.

## Lenses

Each lens is a distinct kind of avoidable complexity, and every one preserves what it must: code behavior, or a human-facing doc's facts. How many proposers they map to is decided in **Dispatch** below.

- **Structure** — unnecessary complexity, nesting, or branching; redundant or duplicated logic; unclear names; related logic that could be consolidated.
- **Cost** — work the change itself added beyond what its result needs, where the excess is evident from reading the diff rather than from a measurement: per-iteration queries or IO that one call covers. Reshape to the same result at the lower cost.
- **Noise** — formatting churn unrelated to the task; comments that merely restate the code.
- **Prose** — human-facing docs only. Give a paragraph one topic; turn an enumeration into a list; keep a condition, exception, or qualifier beside the sentence it governs; use one name for one referent; state a fact once. A long sentence is a signal, not a rule. Reordering, emphasis, headings, sentence breaks, and paragraph breaks are free; the set of facts is not. Never drop an instruction or default, a prerequisite or condition, a side effect, a warning, an opt-in or opt-out entry, or what happens on failure.
- **Reuse** — places where the diff reimplements what the repository already has. Grep the shared and utility modules and the files adjacent to the change, and name the existing helper it should call instead.

## Don't over-simplify

- No clever one-liners or dense expressions just to cut lines; no nested ternaries for multi-branch logic (prefer `if`/`else` or `switch`).
- Keep helpful abstractions and separation of concerns; don't merge unrelated concerns into one unit.
- Don't make code harder to debug, extend, or review.
- Don't optimize speculatively: anything whose justification needs a measurement — a different algorithm for scale, caching, concurrency, precomputed indexes — is out of scope. Report it. Repairing cost the diff itself introduced is not speculative, and the baseline decides which it is: restoring the cost the code had before the change is in scope, making it cheaper than it has ever been is not.

## Dispatch

Proposers are read-only and share no mutable state, so they may run in parallel (`superpowers:dispatching-parallel-agents` — this is independent fact-finding, not implementation). The fan-out is sized to the diff:

- **Default** — one proposer takes every lens.
- **Large diff, or one spanning subsystems** — one proposer per lens, dispatched together.

**Prose is assigned only when the diff contains human-facing docs.** With none, no proposer takes it: the default proposer's lens set is one smaller, and per-lens fan-out gains no worker. With docs present, per-lens fan-out gains the one Prose proposer, and the default proposer adds the lens.

Dispatch a fresh proposer each round and give it the diff as it now stands, not the previous round's proposals — a proposer shown what was just applied anchors on it. Inline **Scope**, **Lenses**, **Proposal contract**, and **Don't over-simplify** into the prompt so the proposer doesn't go hunting for them, and confine its searches to the project root or narrower.

## Proposal contract

Each proposer returns proposals only — never an edited file — with:

- **location** — `path:line` within the diff, numbered as the file now stands.
- **lens**.
- **change** — what the code should say instead.
- **behavior preservation** — why the change cannot alter behavior, and which existing check would catch it if it did. When no existing check can prove it, propose the minimal characterization test that would, per **Scope**.

**For human-facing docs, preservation is a judged claims table, not a check.** A doc proposal returns its before range, its exact after text, and two tables:

- **before and after tables** — one row per fact a reader acts on or relies on, each labelled with the category it belongs to: instruction, default, prerequisite, condition, side effect, warning, opt-in / opt-out, failure behavior. Both tables cover the before range the proposal replaces.
- **row-set equality is the proof** — order does not matter and a duplicated fact folds into one row. A fact the after text states that the before did not is an addition and out of scope. A fact that leaves the replaced range is preserved only when the after table names, as `path:line` in the same file and outside the replaced range, where it still stands; that is how removing a duplicate stays inside row-set equality.
- **byte-identical tokens** — commands, flags, numbers, versions, paths, URLs, link targets, code blocks, and the headings a link points at.
- **the exact after text**, which the judge returns unchanged when it accepts. Different wording is a reject, or a fresh after table verified again.

Report "no proposals" explicitly rather than inventing one.

## Pass

1. Gather the inputs: the diff and the paths it touches.
2. Dispatch proposers against the diff, sized per **Dispatch**.
3. Hand `judge-findings` every proposal of the round as an item, the lens in place of severity and no candidates, judged against the resolved **Scope** — with **Scope**'s "preserve code behavior exactly" as the requirement for code, and, for a human-facing doc, the judged claims table that proves its facts. For a doc proposal, hand it the before range, both claims tables, and the exact after text as well. Hand it the earlier rounds' record — proposals accepted, proposals rejected with the reason, proposals set aside with the question put to the person — and, as the acceptance criteria, **Scope**, **Lenses**, and **Don't over-simplify**. A proposal it returns as `needs-user` is not applied: it is set aside, its question joins that record, and it is not actionable for step 5, so a round left with only set-aside proposals ends the pass clean.
4. Apply the accepted proposals yourself. Never apply two in the same round whose before ranges overlap, or where a residual location one names falls inside the other's before range: apply one, and let the next round propose the other against the file as it now stands, so the applied text always matches the table the judge verified. Then run the checks the project defines — in its README, Makefile targets, package scripts, or CI config — and read their actual output. For a doc proposal no project check proves its facts, so the proof is the judged table's agreement with the text you applied. Code proposals keep the check or the characterization test, and a claims table never stands in for either. When it applied nothing, skip that check run only when the caller passed, as an input to this invocation, a check result covering the tree it invoked this skill on.
5. Loop back to step 2 with a fresh proposer while actionable simplification remains, subject to **Convergence**.
6. Report per **Report**.

## Convergence

This pass's loop stops per `using-dude`'s **Loop convergence**. A round here is one dispatch → judge → apply → verify cycle, and two proposals are the same finding when they target the same location with the same change, however the wording moved — including one re-raised after it was rejected.

## Report

- the fan-out used
- what changed, and what behavior was preserved — or, for a human-facing doc, the judged claims table that proved its facts survived, naming that the applied text is the text the judge accepted
- proposals rejected, with the reason
- the checks that ran, and what they actually printed — or that the check run was skipped as unchanged, citing the covering result the caller handed over, and for a doc change where no project check covers the prose, say the judged table is the proof rather than claiming a check
- any simplification left undone, including anything reported instead of changed, and each proposal set aside as `needs-user` with its question
