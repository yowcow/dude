# dude

![Dude Workflow](docs/dude.png)

Yet another AI workflow.

dude packages the skills that carry a change from an issue to a pull request
whose CI passes and whose review is clean, and the skills that root-cause a
problem before any change is proposed. Merging is left to a person, and so is
everything that depends on it. They are written to wire into one another: each
names the next flow rather than absorbing it, and each has its own gate.

## Skills

| Skill                     | What it produces                                                                   |
| ------------------------- | ---------------------------------------------------------------------------------- |
| `using-dude`              | The workflow rules the other skills are wired by                                   |
| `plan-work`               | An agreed design plus a numbered TODO list at PR granularity                       |
| `implement-work`          | A draft PR on a pushed branch of verified commits, for one PR-sized task           |
| `pr-to-ready`             | A PR whose CI passes and whose review is clean                                     |
| `review-plan`             | Findings on a TODO list or an implementation plan                                  |
| `review-code`             | A diff, branch, or working tree reviewed, with no blocking finding left unresolved |
| `review-findings`         | Findings on a findings or judgment report, before it becomes the canonical record  |
| `simplify-code`           | Recently changed code simplified, behavior preserved                               |
| `investigate-performance` | An evidence-backed explanation of a performance shortfall                          |
| `investigate-anomaly`     | A blameless findings report on a failure, incident, or drifting metric             |
| `investigate-question`    | A judgment on an open question, with the evidence that settles it                  |

The change flow is `plan-work` → `implement-work` → `pr-to-ready`, entered at
whichever stage the work has actually reached. An investigation —
`investigate-question`, `investigate-anomaly`, or `investigate-performance` —
runs first when there's a cause to find or a question to settle, and hands
its findings to `plan-work`.

## Requirements

dude requires [Superpowers](https://github.com/obra/superpowers#installation). Install it first, in the same runtime you are installing dude into. dude's skills name Superpowers procedures and neither ship nor reimplement them, so those calls have nowhere to go until Superpowers is present.

## Install

OpenCode:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "dude@git+https://github.com/yowcow/dude.git",
    "superpowers@git+https://github.com/obra/superpowers.git",
  ],
}
```

Put `$schema` and both `plugin` entries in the global
`~/.config/opencode/opencode.jsonc`, then restart OpenCode.

Claude Code:

```
/plugin marketplace add yowcow/dude
/plugin install dude@dude
```

Codex:

```
codex plugin marketplace add yowcow/dude
codex plugin add dude@dude
```

Codex records hook trust per hook rather than per plugin — `~/.codex/config.toml`
gains a `[hooks.state."dude@dude:hooks/hooks.json:session_start:0:0"]` entry
carrying a `trusted_hash`. Installing dude does not grant it: `codex plugin add`
records no such entry, and an untrusted hook does not run, so `using-dude` is
not in context until you trust it — though the skills are still invocable
by name. Codex asks at the start of the next interactive session instead: after
the directory-trust prompt, a `Hooks need review` prompt offers to review the
hook, trust it, or continue without trusting. Codex's hook trust decides whether
injection happens at all.

## Versions

dude is not versioned. Every runtime is meant to carry the default branch's
latest commit, so there is no release to cut and nothing to bump. Which manifest
carries a `version` at all follows from what each runtime does with one:

| Runtime     | Requires `version`?        | Uses it to decide an update?                              |
| ----------- | -------------------------- | --------------------------------------------------------- |
| OpenCode    | yes                        | no, git-backed installs do not use it to decide an update |
| Claude Code | no — `validate` only warns | **yes — a version left in place stops updates**           |
| Codex       | yes, strict semver         | no                                                        |

So the two manifests Claude Code reads — `.claude-plugin/plugin.json` and the
plugin entry in `.claude-plugin/marketplace.json` — carry no `version`.
`claude plugin update dude@dude` compares commits instead, and the version it
reports is a short commit sha. An install made while those manifests still said
`0.1.0` moves onto sha-tracking at its first `claude plugin update`, so nobody
has to reinstall. `claude plugin validate .` warns that no version is specified;
that warning is the expected state here, not something to fix.

`.codex-plugin/plugin.json` and `package.json` keep `"version": "0.1.0"`
because their formats require one — and **that value is never bumped**, because
neither git-backed route reads it to decide an update. Codex installs the
marketplace snapshot's root directory itself, with no per-version cache in
between. OpenCode caches the commit first installed for an unchanged git spec; restarting,
removing and re-adding the config entry, or rerunning `opencode plugin` with that
spec does not refresh it. To update to HEAD, quit OpenCode, remove
`~/.cache/opencode/packages/dude@git+https:/github.com/yowcow/dude.git`, and
restart.

What each runtime printed when this was measured — and the throwaway plugins the
version-less control was taken with — is recorded in
[issue #42](https://github.com/yowcow/dude/issues/42).

## Use

An investigation is optional, and runs before `plan-work` only when there's a
cause to find or a question to settle first:

```mermaid
flowchart LR
    issue[Issue]
    invq[investigate-question]
    inva[investigate-anomaly]
    invp[investigate-performance]
    plan[plan-work]
    impl[implement-work]
    pr[pr-to-ready]

    issue --> plan
    issue -. optional .-> invq --> plan
    issue -. optional .-> inva --> plan
    issue -. optional .-> invp --> plan
    plan --> impl --> pr
```

### A typical run

A run starts with an issue and ends with a pull request waiting for a person to
merge it — that issue plus three prompts, across three kinds of session:

1. **Open an issue** for what you want done. It is what the plan gets published
   against, and the parent the sub-issues hang from.

2. **Plan it, in one session:**

   ```
   /dude:plan-work <issue-url>
   ```

   It researches, agrees a design with you, then publishes that design plus a
   numbered TODO list at PR granularity as one comment on the issue, and opens
   one sub-issue per item.

3. **Implement each item, one fresh session per sub-issue:**

   ```
   /dude:implement-work <sub-issue-url>
   ```

   It takes the item to a draft PR on a pushed branch of verified commits, and
   ends by naming that PR's URL.

4. **Take that PR to ready, in another fresh session:**

   ```
   /dude:pr-to-ready <pr-url> (ready-on-clean=yes)
   ```

   It resolves the branch, base and repository from the PR, sets up its own
   worktree, then loops on CI and review until both are clean.

Then wait for the PR.

Steps 3 and 4 are separate sessions rather than two prompts in one because the
second flow's cost is dominated by re-reading the first's context: measured over
126 runs, the stretch after `pr-to-ready` starts is 41% of the session's cost,
and starting it fresh drops what it re-reads each turn from roughly 269k tokens
to roughly 60k. Handing it the PR URL is what makes that split practical — the
reference is the whole entry, so no branch name has to be remembered and no
checkout prepared by hand.

A run's sessions need not all be at the same tier. `plan-work` is where a
design gets agreed and a bad call is expensive to undo, so give it the highest
tier you have; `implement-work` and `pr-to-ready` mostly execute and inquire,
and a cheaper tier carries their main loops. Three sections below are what that
leaves you to handle: **What tier a marked worker runs at**, for keeping the
marked workers high once the session under them is cheap,
**What the run's own tier decides**, for the judgments that come down with the
session instead of staying with those workers, and **What else the run's cost
rides on**, for the session length and worker count that remain after the
model is cheap. Whether a cheap main loop still
runs `implement-work`'s gates and `pr-to-ready`'s clean judgment at the same
fidelity is not settled here, so nothing below reports that it holds. That
unsettled question does not reach **What the run's own tier decides**, which
records a different thing: where those judgments run, and what a lowered tier
costs them.

Only the first name on each of those lines is a slash command: Claude Code
passes everything after it to the skill as free text. That is what makes
`ready-on-clean=yes` usable — it answers in the same breath the one question
`pr-to-ready` would otherwise stop and ask, whether a clean run should mark the
PR ready. It is not a parsed flag; the argument text is read rather than matched
against a grammar, and it is Claude Code's pass-through that was measured, not
the other runtimes'.

A fresh session per sub-issue is the shape rather than a preference: a later PR
is never a continuation of the previous one and inherits none of its
verification. And dude stops at ready — merging, closing the parent issue, and
deleting the branch and worktree are yours.

### How each runtime reaches the skills

| Runtime     | `using-dude` in context at session start?                                                     | How to reach it by hand |
| ----------- | --------------------------------------------------------------------------------------------- | ----------------------- |
| OpenCode    | yes — a summary stub via `experimental.chat.messages.transform` on the first user message     | —                       |
| Claude Code | yes — a summary stub via a SessionStart hook                                                  | —                       |
| Codex       | yes, once the hook is trusted — the same stub via `hooks/hooks.json`                          | `dude:using-dude`       |

Each row's evidence is in the prose below.

OpenCode's package plugin registers all of dude's skills and prepends a summary
stub of `using-dude` — the same stub sentences as the hook stub under a different envelope — to the first user
message through `experimental.chat.messages.transform`, so the stub is in
context at session start and the full rules load on a `dude:using-dude` skill
call. The injected text uses a dude-only marker
and does not contain `EXTREMELY_IMPORTANT`, so Superpowers' bootstrap and
this one do not skip each other. Two loads of the same plugin (a global git
install plus the checkout's `.opencode/plugins/`) still inject once.

Claude Code needs no invocation: a SessionStart hook injects the ~0.6KB summary
stub inline at the start of every session; the full rules load on a
`dude:using-dude` skill call.

Codex installs all of dude's skills and runs the shared `hooks/hooks.json` once
the hook is trusted, receiving the same stub — the Install section above
covers what trust involves. The `dude:using-dude` skill works whether the hook is
trusted or not.

The skill bodies use bare names (`plan-work`), because the `dude:` prefix is a
plugin namespace the host adds.

### What tier a marked worker runs at

A marked worker dispatched without a model of its own lands on the runtime's
subagent default rather than the run's own tier, which only takes over when no
default is set — so raising the run's own tier does not reach the worker where
the default sits below it. An explicit `model` argument on the dispatch
overrides that default outright, even to a lower tier — so the default being
set correctly is not evidence that every marked dispatch honors it. On Claude
Code the default is the environment variable
`CLAUDE_CODE_SUBAGENT_MODEL`, not a `settings.json` key; set it to the highest
tier you have and leave it there regardless of the run's own tier.

Effort is a second, separate ceiling: on
Claude Code a worker runs at the session's own effort and no dispatch can
raise it above that, even where its model lands on the highest tier. Launch even
a cheap main-loop session at the effort you want its marked workers to have.

Confirming the ceiling actually held takes two checks, not just the first:
the default against the environment
(`env | grep CLAUDE_CODE_SUBAGENT_MODEL`), then each marked worker's own
transcript for what model and effort it actually ran on — a self-report is
the worker's own account, not the runtime's record of the call
([measurements](https://github.com/yowcow/dude/issues/169#issuecomment-5535611330);
[full classification](https://github.com/yowcow/dude/issues/266#issuecomment-5611590258)).
This was measured on Claude Code alone; where a runtime carries no such lever,
`using-dude`'s **Worker tier** leaves it undecided, so leave the main loop's
tier alone there.

### What the run's own tier decides

A review finding's verdict goes out to marked workers, but `implement-work`'s
two gates, `pr-to-ready`'s clean check and `simplify-code`'s accept/reject stay
in the main loop and come down with its tier. The run still reports _clean_,
and no gate in the flow catches the drop.

### What else the run's cost rides on

Cost doesn't ride on tier alone: a grown session's per-request cost rises from
re-reading context, eating the cheap-tier saving, and the total is dominated by
worker count, which lowering the main loop's tier does not reduce
([measurements](https://github.com/yowcow/dude/issues/169#issuecomment-5534943995);
[correction](https://github.com/yowcow/dude/issues/169#issuecomment-5535611330)).

The subagent default also carries the four roles that no skill marks —
`implement-work`'s plan drafter, `simplify-code`'s proposer, and the
execution method's per-task reviewer and per-task implementer. Dispatched
without a `model` of its own, each rides the same ceiling that **What
tier a marked worker runs at** above sets for the marked workers'
sake. Across 158 Claude Code dispatches of those four roles, the
58 with no `model` argument all landed on Opus, at $121 over a
four-day window, and the 100 with one all landed off Opus — the
`implement-work` plan drafter alone accounted for $69 of that $121
([measurements](https://github.com/yowcow/dude/issues/267#issuecomment-5612054475)).
The only lever available is naming a cheaper model at the dispatch itself;
lowering the default would pull the marked workers down with it
([yowcow/dude#266](https://github.com/yowcow/dude/issues/266)).

## Development

Point a marketplace at a local clone instead of the remote:

```
/plugin marketplace add ~/repos/dude
/plugin install dude@dude

codex plugin marketplace add ~/repos/dude
codex plugin add dude@dude
```

Starting OpenCode from the repository checkout loads
`.opencode/plugins/dude.js` as a project plugin. Temporarily remove any globally
configured dude plugin entry first, then use the native `skill` tool to verify
every local skill.

The checkout's transform and the hook emit the same stub: try hook changes by
editing `hooks/session-start` and `tests/hooks/session-start_test.sh` in place,
and keep `.opencode/plugins/dude.js` repeating those stub sentences verbatim.

Installing dude a second time under a throwaway name is not a way to try hook
changes out. Two installs run the `SessionStart` hook twice, and both blocks
reach the same session. Which tree each one came from is readable — the injected
text names the install path it ran from — but the session is still carrying
the stub twice, counted twice against the context in two near-identical blocks.
Neither block carries the rules — both are static summaries — so invoke
`dude:using-dude` from the intended install for the full rules. Uninstalling the github-sourced
`dude@dude` first is what avoids that, and it rewrites somebody's plugin
environment — ask whoever owns it.

The hazard is the hook running twice, so it is not specific to Claude Code:
Codex runs `hooks/hooks.json` too, once the hook is trusted. Whether a second
Codex install injects twice as well has not been measured here.

Check the manifests before installing:

```
make manifest
```

`claude plugin validate` starts from `.claude-plugin/marketplace.json` and reaches that same
`plugin.json` through the entry's `"source": "./"`, which is where its `No version
specified` warning comes from — expected here, per the Versions section above.
The Codex validator reads `.codex-plugin/plugin.json` and walks every `SKILL.md`
as well, so it catches malformed frontmatter at the same time. Neither manifest
validator covers `.agents/plugins/marketplace.json`, `package.json`, or
`hooks/hooks.json`, so `make manifest` JSON-parses those three files, syntax
only. `make lint test` still does not run manifest validation: it covers shell
and the test suite.

`AUTHORING.md` holds the rules for writing and editing these skills — where
each kind of text belongs, and the deletion test every sentence has to pass.

## License

MIT. See `LICENSE`.
