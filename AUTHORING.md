# Authoring dude's Skills

`using-dude` is the single source of the workflow rules, installed to OpenCode, Claude Code, Codex, and Muse Code alike; rules that are not about the workflow are out of scope here. Everything below binds every file in this repository — `using-dude`'s `SKILL.md`, every other `SKILL.md`, and everything they carry. When updating any of them, prefer consolidation and simplification over appending, and leave no duplicated or stale text behind, except where **Duplication and rationale** below says otherwise.

What all of this protects is one thing: that the basic flow — `(investigate-*, settle-question, audit-code →) plan-work → implement-work → pr-to-ready` — reads fluently enough to run, review gates included. Preparation for rare exceptions is deliberately not built in. The run stops and asks a person instead.

## Where each thing lives

Four layers, and the boundary is what keeps each one readable. The layers are not new; letting them blur is what has cost.

- **`using-dude`'s `SKILL.md` — rules only.** Every other skill cites it by name, so every flow leads back to it — no file in the repository costs more per sentence.
- **A skill's `SKILL.md` — policy and procedure only.** It carries **no command blocks**: what to achieve and in what order, never the exact invocation.
- **`scripts/` — mechanism counter-intuitive enough to get written wrong.** A script is executed, not read, so its cost is paid only when it runs. Commands, flags, and the way their results are tested live here.
- **`references/` — rationale.** Read on demand, when a decision needs its reason.
- **A skill's frontmatter `description` — when to use it, and nothing else.** Its purpose and trigger words, stopping short of mechanism; it has to stand on its own, because it is read without the body. The body's **Orchestration model** is mechanism's single source.

## The deletion test

One question, asked of every sentence: **without it, what does the AI do?** The same question is asked before an issue is opened, of a script or a test row as much as of a sentence, and again when the tool it works around gains the capability itself.

This question is about the text's absence. What happens when the text is present — where a guard fires, how contained the resulting damage is — is not an answer to it.

- **(a) It behaves correctly** → delete it.
- **(b) It stops and asks a person** → delete it. That is the wanted behavior, not a failure to prevent.
- **(c) It silently returns a wrong result** → keep it — and if it is mechanism, keep it in `scripts/`.

**Claiming (c) costs one sentence of concrete failure**: which command gets run, which value gets read wrong, which branch gets written. "It might get confused" is not that sentence. That sentence names an input a real run has produced or is expected to produce; a failure reachable only by constructing the input is (b). "The sibling does it" is symmetry, not a (c). A wrong result a later gate in the same flow has to catch is (b), not (c). If you cannot write it, the answer was (a) or (b), and the text goes.

Zero can mean two different things: a mechanism nobody has reached, or a rare input inside one that already runs — telling them apart turns on whether the mechanism itself has ever run, not on whether the script holding it does. The first is decided as a feature, on whether it is wanted; the second is this section's test — and deciding the first never exempts the guards already inside it, which still answer their own (a)/(b)/(c).

## Call what already exists

`superpowers:*`, and whatever else your runtime already ships or has installed, own procedures of their own. Where one of them owns the procedure you are about to describe, **name it and stop.** A local skill's job is the wiring — which procedure runs when, what each hand-off carries, where the gates sit — never a second copy of the procedure itself. A copy is what goes stale silently: the original moves and nothing here says so.

Name the procedure, never the runtime that provides it. Everything in this repository is installed to several assistants at once, so a rule that reaches for one runtime's own feature is a rule that silently does nothing in the others.

## Three rules

1. **No command block in a `SKILL.md`, and no named means.** This one is structural rather than a matter of will: there is nowhere in a `SKILL.md` for a command to go, so the question becomes where it *does* go — shared `tools/` or the skill's own `scripts/` if it is worth keeping, nowhere if the deletion test says (a) or (b). Policy and procedure stay portable abstract prose: what to achieve and in what order, never the invocation, flag string, or runtime that provides it — no CLI, no MCP, no `gh`/`git` spelling — so the same sentence runs wherever the plugin runs. A script whose GitHub write is ported onto the facts contract hands that write to the agent's own native operation: the script keeps only the guard before the write and the read-back check after it, so `tests/scripts-have-tests.sh` has nothing to count for the write itself. A write may take several native steps — a review posted as create-pending, add comments, submit — and a step that fails ends the write there: report the state the earlier steps left, such as a pending review still open, and stop, since carrying on past a failed comment submits a review that reads as complete without it. A write no script ever wrapped stays native too: where creating or attaching a record is one native call with no flag-string, parsing, or branching of its own, no script wraps it. The (c): routing that call through the raw `sub_issues` endpoint identifies the child by database id rather than by issue number, so a number passed there silently attaches whichever issue holds that id from whatever repository.
2. **Adding text means naming the (c).** Every addition to anything in this repository carries its one sentence of concrete silent failure, in the change's own description. No sentence, no addition.
3. **A table past three data rows is a case-split, and case-splits are where the built-in preparation for rare exceptions accumulates.** Keep the table only where the rows genuinely differ in kind, compressing the rest to the invariant behind them with "anything else — ask a person" absorbing the tail. Where the table is built from prose, resolve every row — pure and mixed cases alike — against the prior text before pushing; pure cases alone ship drift that review finds one round at a time.

## Dependencies point down

Skills stack in five dependency layers, top down: `using-dude` (workflow rules), flows, parts, components (the behavior parts share), and primitives (the judging every layer above calls). A skill names `using-dude` from anywhere, shared `tools/` and its own `scripts/` for mechanism, and skills in lower layers by name for procedure. It never names another skill's `scripts/` by path or another skill's **Orchestration model**, and it names a skill in its own layer or above only on an edge `tests/skill-deps_test.sh` lists with its reason — that file holds which skill sits in which layer and those reasons.

Shared mechanism lives once, in top-level `tools/`, called through `SCRIPT_DIR` rather than by bare name or cwd-relative path. What stays a script is what the Keep rule keeps: a dude contract (Base-Branch trailer, prerequisite-line base resolution, repo identity checks, merge guards) or a concrete silent failure the script's header names. A generic operation — neither — stays abstract prose under rule 1 and never becomes a script.

A kept script leaves by a replacement test. The unit is the script, or every script its Keep entry covers when it has one; the test passes only if all of these hold, and the unit's scripts, their tests, and the Keep entry are then deleted together:

- The fixture is every behavior-test row of the unit's scripts, argument-check rows excepted.
- The subject and the judge are blind: each is a fresh context that has not seen the unit's scripts or their tests.
- The oracle (the unit's scripts) runs only after every verdict is in.
- Three independent runs agree with the oracle on every row, comparing only the result the caller branches on, not its literal text.
- The prose under test is the exact text that would ship.

A script whose GitHub reads and writes move onto the facts contract (`skills/implement-work/references/facts.md`) skips the replacement test and stays a script: each silent failure its header names moves into that catalogue or into the post-write read-back, and the port's PR says where each one went. A script whose feature is withdrawn — because only one of the means can perform it, or because the design removes the feature — and a shared script a port or a withdrawal leaves with no caller — skips the replacement test too, and is deleted together with its tests, the prose naming it, and its Keep entry.

The contracts those shared tools implement live under `skills/implement-work/references/` and are cited from `tools/` and other skills by path. That direction is intentional and stays: the contracts were written where their first callers lived, moving them churns every header and test that cites them, and the citations are documentation — no script sources another skill's file, every call goes through `SCRIPT_DIR` to an executable.

## Uniform, branch-free behavior

Compose layers from transparent parts: each part does one thing without branching on who calls it, and the combination does the rest. A shared part behaves the same from any caller; a caller-specific case means the structure is wrong and gets refactored, not another branch. (SOLID's single-responsibility and open-closed behind the first sentence, Liskov substitution behind the second, DRY in refusing the duplicated branch.) The (c): a shared script branching on its caller's name silently serves the old default to a new caller, and no gate on the new path reads that branch to catch it.

## Findings that ask for more text

This material has been trimmed and grown back before, every time through the same door: a review finding of the form "case X is missing". Written as the author's own restraint, the deletion test never reaches that door — the author is not the one asking. So it binds the **reader of a finding** too.

**A finding against anything in this repository that asks for text to be added does not stand as a finding requiring action unless it names the (c) — one sentence of concrete silent failure.** Answer such a finding with the question itself: (a), (b), or (c)? Where the answer is (a) or (b), record it and decline; **declining on that ground resolves the finding** — it does not leave a blocking finding open, and does not stall the loop that raised it.

This does not weaken review. A finding that names its (c) is exactly as blocking as before, and nothing here touches review of code.

## Duplication and rationale

This binds `using-dude` and every other skill alike. A rule's body and the rationale behind it are different things, and the consolidation instruction above governs them differently.

- **A rule body may be restated, and that is the exception.** The test is whether the rule loses at the point it has to bite — because the reader got there without its source, or because something read at that point competes with it. `using-dude` is installed alongside the other skills and reachable by name, and every citation writes that name, so a skill being readable on its own does not make the first case hold; the competing instruction is what usually earns the restatement, as with the sub-skill call-site rule under **Workflow** in `using-dude`. Where neither case holds, the copy is inertia: cut it and depend on the single source's name. A skill's own *procedure* still has to stand alone, which is completeness rather than duplication.
- **Rationale is single-source.** Keep it beside the rule only where its absence gets the rule misapplied. A second case keeps it: rationale recording **why an obvious alternative is wrong**, which consolidation would otherwise strip as redundant. **Delete the rest**; git history and the issue hold it. What stays sits beside its rule, and one or two sentences always do. Only rationale past that floor *and* spanning several rules becomes a *candidate* for the skill's `references/` — it moves only once the gathered whole reads as its own document, and holding one is what gives a skill that directory. Don't split to save tokens; the same run may read both. Legibility is the gain. `using-dude` has no `references/` of its own, so there the choice is keep or delete.
- **SessionStart stub sentences are restated across emitters.** The four stub sentences live canonically in `hooks/session-start` and are repeated in `.opencode/plugins/dude.js` (plus a pointer in `skills/using-dude/SKILL.md` and prose in `README.md`). The test in `tests/opencode-plugin_test.sh` pins the repetition: the four stub sentences are compared whole across the two emitters, with only the install path and the cksum derived from it normalized. The (c): a divergent copy silently injects different workflow rules per runtime with no gate catching it.
