---
name: review-code
description: Use to review code.
---

# Review Code

Use on code in any state — a fresh diff, a branch, or an uncommitted working tree.

One invocation runs the loop to completion: review, judge, fix, verify, review again, until no blocking finding remains. Re-entry is the caller's — reviewing again after something else changed the code belongs outside this pass.

## Orchestration model

**This skill dispatches no worker of its own: each round's reviewer and verdict workers are `vet-code`'s.**

- The orchestrator owns the loop: it resolves the scope, calls `vet-code` each round, applies the accepted fixes, verifies, and decides when the loop ends.
- Fixes are applied, never committed — commits are the caller's.
- Report each round to the caller in chat and never to GitHub, per `using-dude`'s **Stage boundaries**.

## Scope

Resolve what to review in this order, and declare the resolved scope before dispatching anything:

1. **Caller-supplied** — a SHA range, paths, or a PR. Use it as given; a PR becomes the range `tools/resolve-range.sh` bounds for it.
   - Before that, run `tools/check-pr-author.sh`: on `OTHER`, apply nothing and stop — this loop rewrites the code it reviews, and that code is somebody else's. On `STOP`, report it and stop. On `SELF`, go on.
2. **Uncommitted changes present** — the working tree diff: staged, unstaged, and untracked files.
3. **Clean tree, commits ahead of `<base>`** — run `tools/resolve-range.sh` with no argument.
   - `<base>` is resolved, not assumed: the `Base-Branch:` trailer `implement-work` records is read back and the base settled from that PR's present state, falling back to the default branch where there is no trailer. The trailer's contract and the state-to-base table live in `implement-work`'s `references/base-branch.md`, never duplicated here.
4. **Nothing to review** — no uncommitted change, and no range with anything in it. Ask the user what to review. Never widen to the whole repository on a guess.

`tools/resolve-range.sh` answers in one line: `RANGE <base>..<head>` — the two SHAs to review. `EMPTY` — the range holds nothing; fall through to 4. `STOP` — the base could not be settled; report it and stop, rather than reviewing a range that may be somebody else's. Either script answers `NEED` while it needs facts: read what it names as `implement-work`'s `references/facts.md` defines them into one facts file and run it again with `--facts <file>`, for as long as it asks.

## Pass

One invocation is one pass, and a pass is as many rounds as it takes:

1. Resolve the scope per **Scope**.
2. Invoke `vet-code` once on the code as it now stands, handing it the scope, the requirements, the ledger rows the caller handed over unchanged, and from the second round on the earlier rounds' record.
3. Take back the judged findings `vet-code` returns — each `accept` with its fix, `reject` with its reason, or `needs-user` with its question — and re-judge none of them; carry any caveat it returns (paths-only scope, no requirements) into **Report**. With them comes one answer per ledger row: the finding it became, keeping the row it came from, or a `Ledger row closed` or `Ledger row declined` line as the worker returned it. A closed row is answered for its round — it takes no verdict, joins no earlier rounds' record, and is handed to no judge, whose only candidates are `Declined to judge` lines; the ledger re-hands it to the next round, which answers it again from the code as it then stands.
4. Count the `needs-user` verdicts before applying anything: one or more ends the pass's rounds here with the meaning `judge-findings`'s **Verdicts** gives `needs-user` — go to step 7 and leave non-clean, per **Escalation**. Otherwise apply only findings whose verdict is `accept` yourself — severity does not decide this — except one that invalidates the approved design, which is not fixed here at all: stop the pass, per **Escalation**. Never fix a `Declined to judge` line itself; fixing straight from the reviewer's text silently applies work the judge never accepted.
5. Verify with the concrete checks the project defines — in the README, Makefile, package scripts, or CI — and read their actual output. When this step applied nothing, skip this check run only when the caller passed, as an input to this invocation, a check result covering the exact tree this invocation ran on.
6. Return to step 2 while a blocking finding remains, subject to **Escalation**. A pass that ended on a `needs-user` does not come back here.
7. Report per **Report**.

A round is one review → judge → fix → verify cycle. The pass is clean per `using-dude`'s **Loop convergence** loop-clean when a round's review produces no Critical or Important finding and no verdict came back `needs-user`. Verdict decides what gets applied; severity decides what blocks.

## Escalation

This loop stops per `using-dude`'s **Loop convergence**.

- **Pass** says what a round is here, and two findings are the same when a later round faults the same location on the same grounds, however the wording moved — including a claim restated after a fix meant to resolve it.
- A round that trips either of **Loop convergence**'s two non-clean conditions still applies and verifies its accepted findings before the loop ends; it just doesn't start another review.
- **A `needs-user` verdict stops the pass non-clean**, with the meaning `judge-findings`'s **Verdicts** gives `needs-user`: the round that stopped applied nothing, and the caller hands the finding to a person.
- A Critical finding that invalidates the approved design is not fixed in this loop: per `using-dude`'s **Escalation** it goes back for re-approval — this skill is no exception — handed over as the finding itself, reported apart from the ordinary verdict so the caller routes it rather than reading the pass as merely unfinished.

## Report

- the scope reviewed and how it was resolved, including whether requirements were available
- the number of rounds run
- accepted findings, with location and what changed
- rejected findings, with the reason
- on a `needs-user` stop, the stopped round's verdicts as they stand unapplied — each `accept` with its proposed fix, each `reject` with its reason, and each `needs-user` finding with why the worker put the decision to a person. Earlier rounds report in the applied form above.
- each ledger row the caller handed over, one line for each: the row, then fixed, or declined with the reason — that it no longer stands, that the finding it became was rejected, or that the earlier rounds' record already holds it as rejected; where the record already holds the row as rejected, the reason is that record's, the one step 2 hands to `vet-code` from the second round on, never reconstructed from the code; a row that no longer stands carries the `Ledger row closed` reason the worker returned for it, unchanged. A row whose finding an earlier round accepted and fixed reports `fixed` only where this round's answer still closes it, that earlier fix being the evidence it no longer stands; a later fix that brought the condition back hands the row to this round as the finding it returned; only a row this round returned as a finding, nothing closing it, reports `open` — the finding it became is still open at this stop
- what verification ran, and its actual result — or that verification was skipped as unchanged, citing the covering result the caller handed over
- the verdict: clean, or the blocking findings that remain — flagging separately any Critical finding that invalidates the approved design, per **Escalation**
