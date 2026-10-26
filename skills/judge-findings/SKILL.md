---
name: judge-findings
description: Use when another skill needs review findings judged accept, reject, or needs-user outside its own main loop.
---

# Judge Findings

The reviewer, applying a fix, every round decision, and posting anything anywhere are the caller's. This skill edits nothing and posts nothing.

## Inputs

- **The items** — each finding as the reviewer stated it, with its severity and location; and each candidate, a line the reviewer raised but declined to judge, marked as a candidate. A doc proposal carries, in place of a fix, its before range, its before and after claims tables, and its exact after text.
- **What to judge against** — the scope (a committed range, uncommitted changes, or paths, with the read-root when the caller has one), or the artifact under review.
- **The requirements.**
- **The earlier rounds' record** — findings accepted and fixed, findings accepted and recorded without a fix, findings rejected with the reason, and candidates rejected with the reason.
- **The caller's own acceptance criteria**, which every worker gets verbatim.
- **The measurement record's path** — when the caller has one covering the subject judged, per `using-dude`'s **Measurement records**.

## Orchestration model

**Judging never happens in the caller's main loop.** The main loop may have written the code or fixed it, so a verdict reached there rests on its own account of why the code reads this way, and a real finding rejected on that account is rejected for good — no later round reads it again.

- No items, no worker.
- Otherwise group the items into a few workers launched together — one when the items are few — keeping items at nearby locations, such as the same file or the same section, in the same worker.
- Each worker applies `superpowers:receiving-code-review` to each of its items and returns one verdict per item. It gets its items and every input above, never the main loop's history. It is read-only: it edits nothing, runs no project check, and returns the fix as text; applying it is the caller's. It reads the measurement record it was handed, and where that record does not cover the claim, it says what would have to be measured.
- Workers go out at the `high` tier in `using-dude`'s **Worker tier**.

## Verdicts

- **`accept`** with the fix — only after verifying the claim against what is judged. It judges the claim alone: whether the fix is applied is the caller's decision, and an `accept` recorded without being applied stays an `accept`. Every `accept` also carries a value and its reason, a separate axis from the severity the reviewer gave and from the `reject` ground below:
  - **`apply`** — the fix changes what someone does: what the code does when it runs, a command that gets run, a test that gets written, a procedure that gets followed, or a decision a maintainer makes when maintaining it.
  - **`record`** — the fix changes only what a reader takes away, and none of those actions.
  - Severity does not decide the value: a Minor can be `apply` and an Important can be `record`. A fix that changes nothing a reader takes away is not on this axis; it is the reviewer preference under `reject`.
- **`reject`** with the stated reason — the finding is wrong, only reflects reviewer preference, asks for work beyond the request, or fails the caller's criteria.
  - **A fix that changes nothing a reader takes away is reviewer preference** — a sentence reworded, a paragraph reflowed, a list reordered, a name or style the reviewer would have written differently. It takes `reject`, not `needs-user`, unless the caller's acceptance criteria make that class of change the work.
- **`needs-user`** — the call is a person's rather than a technical one: the question to put to that person and why the decision is theirs.
  - **A claim resting on a measurement the record does not cover** — never `reject` on that ground. It takes `needs-user` on the **measurement route**: whoever may spend that measurement — the caller, or the caller above it where that caller runs no project check — takes it, one and bounded, and has the claim judged again. Only where neither may spend it does it become the **person route**, with the `not measured` line.

For a candidate, `accept` or `needs-user` makes it a finding at the severity the worker assigns, carrying that verdict; `reject` leaves it declined.

**A doc proposal is judged against the file and the proposed text, never against its own table.** For a doc proposal, enumerate the facts of the replaced before range from the file yourself, and the facts of the proposed text from that text, then compare both directions against both tables — the categories the tables cover are not the measure. A fact the after text adds fails; one it removes fails unless the after table names the `path:line`, in the same file and outside the replaced range, where that same fact still stands. Confirm that commands, flags, numbers, versions, paths, URLs, link targets, code blocks, and the headings a link points at are byte-identical. A missing, empty, or thin table, or a dropped warning, condition, instruction, or opt-out, is not accepted. On `accept`, return the proposer's after text unchanged: different wording is a `reject`, or a fresh after table verified again.

Return each item as given, with its verdict — an `accept` with its value and reason. The caller re-judges none. The caller records the return whole and unreworded into `judge-verdict-<round>.md` per `implement-work`'s `references/measurement-record.md`, carrying the input's identity with it; a reworded fix silently turns a `record` accept into a fix. For a claim that rests on a measurement the measurement record did not cover, also return a `not measured` line naming what would have to be measured.
