---
name: judge-findings
description: Use when another skill needs review findings judged accept, reject, or needs-user outside its own main loop.
---

# Judge Findings

- Leave the reviewer to the caller.
- Leave every round decision to the caller.
- Leave posting anything anywhere to the caller.
- Edit nothing here.
- Post nothing here.

## Inputs

- **The items** — each finding as the reviewer stated it, with its severity and location.
- **Each candidate** — a line the reviewer raised but declined to judge, marked as a candidate.
- **A doc proposal** — its before range, its before and after claims tables, and its exact after text, in place of a fix.
- **What to judge against** — the scope (a committed range, uncommitted changes, or paths, with the read-root when the caller has one), or the artifact under review.
- **The requirements.**
- **The earlier rounds' record** — findings accepted and fixed, and findings or candidates rejected with the reason.
- **The caller's own acceptance criteria**, which every worker gets verbatim.

## Orchestration model

- Judge nothing in the caller's main loop, since the main loop may have written or fixed the code and a verdict reached there rests on its own account of why the code reads this way.
- Treat a finding rejected on that account as rejected for good, since no later round reads it again.
- No items, no worker.
- Group the items into a few workers launched together.
- Launch one worker when the items are few.
- Keep items at nearby locations, such as the same file or the same section, in the same worker.
- Task each worker with applying `superpowers:receiving-code-review` to each of its items and returning one verdict per item.
- Hand each worker its items and every input above, never the main loop's history.
- Keep each worker read-only: it edits nothing.
- Let it run no project check.
- Take back the fix as text rather than applying it, since applying it is the caller's.
- Send workers out at the `high` tier in `using-dude`'s **Worker tier**.

## Verdicts

- Return `accept` with the fix only after verifying the claim against what is judged.
- Leave whether the fix reaches the code to the caller, since judging ends at the verdict.
- Return `reject` with the stated reason where the finding is wrong, only reflects reviewer preference, asks for work beyond the request, or fails the caller's criteria.
  - Treat a fix that changes nothing a reader takes away as reviewer preference — a sentence reworded, a paragraph reflowed, a list reordered, a name or style the reviewer would have written differently.
  - Return `reject`, not `needs-user`, for such a fix, unless the caller's acceptance criteria make that class of change the work.
- Return `needs-user` where the call is a person's rather than a technical one: the question to put to that person and why the decision is theirs.
  - Return never `reject` for a claim resting on a measurement not handed with it.
  - Take `needs-user` on the **measurement route** there: whoever may spend that measurement — the caller, or the caller above it where that caller runs no project check — takes it, once and bounded, and the claim is judged again.
  - Take the **person route** only where neither may spend it, with the `not measured` line.
- Let severity route nothing here, since which severities reach judging is the caller's decision.
- Take a candidate returned as `accept` or `needs-user` as a finding at the severity the worker assigns, carrying that verdict.
- Leave a candidate returned as `reject` declined.
- Judge a doc proposal against the file and the proposed text, never against its own table.
- Enumerate the facts of the replaced before range from the file yourself, and the facts of the proposed text from that text.
- Compare both directions against both tables, since the categories the tables cover are not the measure.
- Fail a fact the after text adds.
- Fail one it removes, unless the after table names the `path:line`, in the same file and outside the replaced range, where that same fact still stands.
- Confirm that commands, flags, numbers, versions, paths, URLs, link targets, code blocks, and the headings a link points at are byte-identical.
- Accept never a missing, empty, or thin table, or a dropped warning, condition, instruction, or opt-out.
- On `accept`, return the proposer's after text unchanged.
- Take different wording as a `reject`, or as a fresh after table verified again.
- Return each item as given, with its verdict — an `accept` with its fix and reason.
- Re-judge none of them in the caller.
- For a claim resting on a measurement not handed with it, return also a `not measured` line naming what would have to be measured.
