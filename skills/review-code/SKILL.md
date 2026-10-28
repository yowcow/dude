---
name: review-code
description: Use to review code.
---

# Review Code

- Use on code in any state.
- Cover a fresh diff, a branch, or an uncommitted working tree there.
- Run one invocation as one loop to completion.
- Review, judge, fix, and verify, then review again until no blocking finding remains.
- Leave re-entry to the caller, since reviewing again after something else changed the code belongs outside this pass.

## Orchestration model

- Dispatch no worker of its own here, since each round's reviewer and verdict workers are `vet-code`'s.
- Own the loop in the orchestrator.
- Resolve the scope there.
- Call `vet-code` each round there.
- Apply the accepted fixes there.
- Verify there.
- Decide when the loop ends there.
- Apply fixes without committing them, since commits are the caller's.
- Report each round to the caller in chat.
- Post nothing to GitHub there, per `using-dude`'s **Stage boundaries**.

## Scope

- Resolve what to review in this order.
- Declare the resolved scope before dispatching anything.

1. **Caller-supplied** — a SHA range, paths, or a PR.
   - Use it as given.
   - Turn a PR into the range the resolve-range script (`tools/resolve-range.sh`) bounds for it.
   - Before that, run the check-pr-author script (`tools/check-pr-author.sh`) for the PR number.
   - On `OTHER`, apply nothing and stop, since this loop rewrites the code it reviews and that code is somebody else's.
   - On `STOP`, report it and stop.
   - On `SELF`, go on.
2. **Uncommitted changes present** — the working tree diff.
   - Cover staged, unstaged, and untracked files there.
3. **Clean tree, commits ahead of `<base>`** — run the resolve-range script with no argument.
   - Resolve `<base>`, never assume it.
   - Read back the `Base-Branch:` trailer `implement-work` records and settle the base from that PR's present state.
   - Fall back to the default branch where there is no trailer.
   - Keep the trailer's contract and the state-to-base table in `implement-work`'s `references/base-branch.md`, never duplicated here.
4. **Nothing to review** — no uncommitted change, and no range with anything in it.
   - Ask the user what to review there.
   - Never widen to the whole repository on a guess.

- Take the resolve-range script's answer in one line.
- Take `RANGE <base>..<head>` as the two SHAs to review.
- On `EMPTY`, fall through to 4, since the range holds nothing.
- On `STOP`, report it and stop, since the base could not be settled and the range may be somebody else's.
- On `NEED`, read what it names as `implement-work`'s `references/facts.md` defines them into one facts file.
- Run it again with that file for as long as it asks.

## Pass

- Count one invocation as one pass.
- Run a pass for as many rounds as it takes.

1. Resolve the scope per **Scope**.
2. Invoke `vet-code` once on the code as it now stands.
   - Hand it the scope.
   - Hand it what was implemented.
   - Hand it the requirements.
   - Hand it the ledger rows the caller handed over, unchanged.
   - From the second round on, hand it the earlier rounds' record too.
3. Take back the judged findings `vet-code` returns and re-judge none of them.
   - Take each `accept` with its fix.
   - Take each `reject` with its reason.
   - Take each `needs-user` with its question.
   - Carry any caveat it returns into **Report**.
   - Cover a paths-only scope and no requirements there.
   - Take one answer per ledger row with them.
   - Keep the row it came from with the finding it became.
   - Take a `Ledger row closed` or `Ledger row declined` line as the worker returned it.
   - Answer a closed row for its round only.
   - Give it no verdict there.
   - Join it to no earlier rounds' record there.
   - Hand it to no judge there, since that judge's only candidates are `Declined to judge` lines.
   - Let the ledger re-hand it to the next round, which answers it again from the code as it then stands.
4. Count the `needs-user` verdicts before applying anything.
   - End the pass's rounds here on one or more, with the meaning `judge-findings`'s **Verdicts** gives `needs-user`.
   - Go to step 7 there and leave non-clean, per **Escalation**.
   - Otherwise apply only findings whose verdict is `accept` yourself, since severity does not decide this.
   - Fix nothing here that invalidates the approved design.
   - Stop the pass there instead, per **Escalation**.
   - Never fix a `Declined to judge` line itself, since fixing straight from the reviewer's text silently applies work the judge never accepted.
   - On a finding describing a bug, write the failing regression test first and watch it fail, then fix it (`superpowers:test-driven-development`).
5. Verify with the concrete checks the project defines.
   - Cover the README, Makefile, package scripts, or CI there.
   - Read their actual output.
   - Skip this check run when this step applied nothing only where the caller passed, as an input to this invocation, a check result covering the exact tree this invocation ran on.
6. Return to step 2 while a blocking finding remains, subject to **Escalation**.
   - Never come back here from a pass that ended on a `needs-user`.
7. Report per **Report**.

- Count one round as one review → judge → fix → verify cycle.
- Hold a pass clean per `using-dude`'s **Loop convergence** loop-clean when a round's review produces no Critical or Important finding and no verdict came back `needs-user`.
- Let the verdict decide what gets applied.
- Let severity decide what blocks.

## Escalation

- Stop this loop per `using-dude`'s **Loop convergence**.
- Let **Pass** say what a round is here.
- Count two findings as the same when a later round faults the same location on the same grounds, however the wording moved.
- Cover a claim restated after a fix meant to resolve it there.
- Apply and verify a round's accepted findings before the loop ends where it trips either of **Loop convergence**'s two non-clean conditions.
- Start no other review there.
- Stop the pass non-clean on a `needs-user` verdict, with the meaning `judge-findings`'s **Verdicts** gives `needs-user`.
- Apply nothing in the round that stopped there.
- Hand the finding to a person through the caller there.
- Fix no Critical finding invalidating the approved design in this loop.
- Send it back for re-approval per `using-dude`'s **Escalation**, since this skill is no exception.
- Hand it over as the finding itself.
- Report it apart from the ordinary verdict, so the caller routes it rather than reading the pass as merely unfinished.

## Report

- Report the scope reviewed and how it was resolved.
- Say there whether requirements were available.
- Report the number of rounds run.
- Report accepted findings with location and what changed.
- Report rejected findings with the reason.
- On a `needs-user` stop, report the stopped round's verdicts as they stand unapplied.
- Cover each `accept` with its proposed fix there.
- Cover each `reject` with its reason there.
- Cover each `needs-user` finding with why the worker put the decision to a person there.
- Report earlier rounds in the applied form above.
- Report each ledger row the caller handed over, one line for each.
- Give the row there, then fixed, or declined with the reason.
- Cover no-longer-stands, finding-became-rejected, and record-already-holds-rejected there.
- Where the record already holds the row as rejected, give that record's reason, since step 2 hands that record to `vet-code` from the second round on and it is never reconstructed from the code.
- Carry a `Ledger row closed` reason unchanged from the worker where the row no longer stands.
- Report `fixed` for a row whose finding an earlier round accepted and fixed only where this round's answer still closes it, since that earlier fix is the evidence it no longer stands.
- Hand the row to this round as the finding it returned where a later fix brought the condition back.
- Report `open` only for a row this round returned as a finding with nothing closing it, since the finding it became is still open at this stop.
- Report what verification ran and its actual result.
- Report skipped-as-unchanged verification with the covering result the caller handed over.
- Report the verdict: clean, or the blocking findings that remain.
- Flag separately there any Critical finding invalidating the approved design, per **Escalation**.
