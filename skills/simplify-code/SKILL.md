---
name: simplify-code
description: Use to simplify recently modified code and human-facing docs while preserving behavior and stated facts.
---

# Simplify Code

- Run one simplification pass per invocation: propose, apply, verify, propose again, until nothing actionable is left.
- Keep the pass local rather than delegating, since a delegated simplifier draws no boundary against optimizations whose justification needs a measurement.
- Never re-enter on its own, since re-running after something else changed the code or a doc in scope belongs to the caller.

## Orchestration model

- Dispatch proposers as the only worker kind, with judging going to `judge-findings`.
- Run everything else in the main loop.
- Task the orchestrator with owning this pass: dispatching the proposers, handing their proposals to `judge-findings`, applying the accepted proposals, verifying, and reporting.
- Let the orchestrator decide when nothing actionable remains, never a proposer.
- Keep proposers read-only: each gets the diff, the paths it touches, and its assigned lenses, and returns proposals only.
- Never let a proposer return an edited file, run the project's checks, or declare the pass clean.
- Dispatch proposers at the `high` tier in `using-dude`'s **Worker tier**, since that buys a fresh context unanchored on why the code ended up this way.
- Treat a proposal no proposer returns as nothing actionable.

## Scope

- Resolve what to simplify in this order, and declare the resolved scope before dispatching anything.

1. **Caller-supplied** — a SHA range or paths. Use it as given.
2. **Uncommitted changes present** — the working tree diff: staged, unstaged, and untracked files.
3. **Clean tree** — the commits ahead of the base the caller names; on a direct invocation, ask the user for the range instead of guessing it.
4. **Nothing to simplify** — no uncommitted change, and no range with anything in it. Ask the user what to simplify. Never widen to the whole repository on a guess.

- Judge docs in scope by role, not by path.
- Simplify a human-facing doc — prose a person reads to install, operate, or understand the project, such as a README, a guide, usage docs, or explanatory text under `docs/` — when the diff touches it.
- Keep agent-facing text out of scope: `SKILL.md`, `AGENTS.md`, `CLAUDE.md`, agent instructions, and the plans or design records an agent reads.
- Keep structured records out of scope too: changelogs, licences, and anything generated or vendored.
- Judge by what the text does, and leave it out when the role is unclear.
- Treat code comments as not docs here; a comment that only restates the code belongs to **Noise**.
- Broaden cleanup only when the user asks.
- Report a worthwhile simplification needing files outside the diff instead of changing it.
- Preserve code behavior exactly: outputs, public APIs, data migrations, test intent, and user-visible semantics.
- Keep a human-facing doc's facts instead, per **Proposal contract**'s claims table.
- Add the minimal characterization test that can prove a code simplification behavior-preserving when the existing checks can't, and say so in the report, since that test is the proof rather than scope creep.
- Give a doc change no test, since its proof is the judged claims table and no check stands in for it.

## Lenses

- Treat each lens as a distinct kind of avoidable complexity, with every lens preserving what it must: code behavior, or a human-facing doc's facts.
- Decide how many proposers the lenses map to in **Dispatch** below.

- **Structure** — unnecessary complexity, nesting, or branching; redundant or duplicated logic; unclear names; related logic that could be consolidated.
- **Cost** — flag only work the change itself added beyond what its result needs, where the excess is evident from reading the diff rather than from a measurement, such as per-iteration queries or IO that one call covers.
- **Cost** — reshape that excess to the same result at the lower cost.
- **Noise** — formatting churn unrelated to the task; comments that merely restate the code.
- **Prose** — human-facing docs only.
- **Prose** — give a paragraph one topic.
- **Prose** — turn an enumeration into a list.
- **Prose** — keep a condition, exception, or qualifier beside the sentence it governs.
- **Prose** — use one name for one referent.
- **Prose** — state a fact once.
- **Prose** — reordering, emphasis, headings, sentence breaks, and paragraph breaks are free; the set of facts is not.
- **Prose** — never drop an instruction or default, a prerequisite or condition, a side effect, a warning, an opt-in or opt-out entry, or what happens on failure.
- **Reuse** — name the existing helper the diff should call instead where it reimplements what the repository already has, searching the shared and utility modules and the files adjacent to the change.

## Don't over-simplify

- Avoid clever one-liners or dense expressions just to cut lines.
- Avoid nested ternaries for multi-branch logic, preferring `if`/`else` or `switch`.
- Keep helpful abstractions and separation of concerns; don't merge unrelated concerns into one unit.
- Don't make code harder to debug, extend, or review.
- Don't optimize speculatively: anything whose justification needs a measurement — a different algorithm for scale, caching, concurrency, precomputed indexes — is out of scope.
- Report a speculative optimization instead of making it.
- Treat repairing cost the diff itself introduced as not speculative.
- Let the baseline decide which it is: restoring the cost the code had before the change is in scope, while making it cheaper than it has ever been is not.

## Dispatch

- Run proposers in parallel, since they are read-only and share no mutable state (`superpowers:dispatching-parallel-agents`).
- Size the fan-out to the diff:

- **Default** — one proposer takes every lens.
- **Large diff, or one spanning subsystems** — one proposer per lens, dispatched together.

- Assign **Prose** only when the diff contains human-facing docs.
- With no docs, give the default proposer one fewer lens and gain no worker in per-lens fan-out.
- With docs present, add the one **Prose** proposer to per-lens fan-out and the lens to the default proposer.
- Dispatch a fresh proposer each round with the diff as it now stands, never the previous round's proposals, since a proposer shown what was just applied anchors on it.
- Inline **Scope**, **Lenses**, **Proposal contract**, and **Don't over-simplify** into the prompt, so the proposer doesn't go hunting for them.
- Confine its searches to the project root or narrower.

## Proposal contract

- Return proposals only from each proposer — never an edited file — with:

- **location** — `path:line` within the diff, numbered as the file now stands.
- **lens**.
- **change** — what the code should say instead.
- **behavior preservation** — why the change cannot alter behavior, and which existing check would catch it if it did.
- Propose the minimal characterization test that would prove it when no existing check can, per **Scope**.

- Prove preservation for a human-facing doc with a judged claims table, not a check.
- Cover the replaced before range with both a before and an after table in a doc proposal.
- Give each table one row per fact a reader acts on or relies on, labelled with its category: instruction, default, prerequisite, condition, side effect, warning, opt-in / opt-out, failure behavior.
- Treat row-set equality as the proof: order does not matter and a duplicated fact folds into one row.
- Treat a fact the after text states that the before did not as an addition, which is out of scope.
- Treat a fact leaving the replaced range as preserved only when the after table names, as `path:line` in the same file outside the replaced range, where it still stands; that is how removing a duplicate stays inside row-set equality.
- Keep byte-identical tokens: commands, flags, numbers, versions, paths, URLs, link targets, code blocks, and the headings a link points at.
- Hand over the exact after text, which the judge returns unchanged when it accepts.
- Treat different wording as a reject, or as a fresh after table verified again.

## Pass

1. Gather the inputs: the diff and the paths it touches.
2. Dispatch proposers against the diff, sized per **Dispatch**.
3. Hand `judge-findings` every proposal of the round as an item, the lens in place of severity and no candidates, judged against the resolved **Scope** — with **Scope**'s "preserve code behavior exactly" as the requirement for code, and, for a human-facing doc, the judged claims table that proves its facts. For a doc proposal, hand it the before range, both claims tables, and the exact after text as well. Hand it the earlier rounds' record — proposals accepted, proposals rejected with the reason, proposals set aside with the question put to the person. As the acceptance criteria, hand Scope, Lenses, Don't over-simplify, and that a readability improvement is value worth applying. A proposal it returns as `needs-user` on the measurement route stays actionable for step 5: take that measurement yourself, one and bounded, record it, and hand the proposal back to `judge-findings` with the record. A proposal returned on the person route is not applied: it is set aside, its question joins that record, and it is not actionable for step 5, so a round left with only person-route set-asides ends the pass clean.
4. Apply the accepted proposals yourself. Never apply two in the same round whose before ranges overlap, or where a residual location one names falls inside the other's before range: apply one, and let the next round propose the other against the file as it now stands, so the applied text always matches the table the judge verified. Then run the checks the project defines — in its README, Makefile targets, package scripts, or CI config — and read their actual output. For a doc proposal no project check proves its facts, so the proof is the judged table's agreement with the text you applied. Code proposals keep the check or the characterization test, and a claims table never stands in for either. When it applied nothing, skip that check run only when the caller passed, as an input to this invocation, a check result covering the exact tree this invocation ran on.
5. Loop back to step 2 with a fresh proposer while actionable simplification remains, subject to **Convergence**.
6. Report per **Report**.

## Convergence

- Stop this pass's loop per `using-dude`'s **Loop convergence**.
- Count one dispatch → judge → apply → verify cycle as one round here.
- Count two proposals targeting the same location with the same change as the same finding, however the wording moved, including one re-raised after rejection.

## Report

- Report the fan-out used.
- Report what changed and what behavior was preserved.
- For a human-facing doc, report the judged claims table that proved its facts survived, naming that the applied text is the text the judge accepted.
- Report proposals rejected, with the reason.
- Report the checks that ran and what they actually printed.
- Report a check run skipped as unchanged by citing the covering result the caller handed over.
- For a doc change where no project check covers the prose, say the judged table is the proof rather than claiming a check.
- Report any simplification left undone, including anything reported instead of changed.
- Report each proposal set aside on the person route, with its question.
