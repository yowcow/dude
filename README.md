# dude

![Dudes hanging out at a beachside skate park with pizza and skateboards](docs/dude.jpeg)

Yet another AI workflow.

dude packages the skills that carry a change from an issue to a pull request
whose CI passes and whose review is clean, and the skills that root-cause a
problem before any change is proposed. Merging is left to a person, and so is
everything that depends on it. They are written to wire into one another: each
names the next flow rather than absorbing it, and each has its own gate.

## Skills

| Skill | What it produces |
| --- | --- |
| `using-dude` | The workflow rules the other skills are wired by |
| `plan-work` | An agreed design plus a numbered TODO list at PR granularity |
| `implement-work` | A draft PR on a pushed branch of verified commits, for one PR-sized task |
| `pr-to-ready` | A PR whose CI passes and whose review is clean |
| `review-plan` | Findings on a TODO list or an implementation plan |
| `review-code` | A diff, branch, or working tree reviewed, with no blocking finding left unresolved |
| `simplify-code` | Recently changed code simplified, behavior preserved |
| `investigate-performance` | An evidence-backed explanation of a performance shortfall |
| `investigate-anomaly` | A blameless findings report on a failure, incident, or drifting metric |

The change flow is `plan-work` → `implement-work` → `pr-to-ready`, entered at
whichever stage the work has actually reached. An investigation runs first
where the cause is unknown, and hands its findings to `plan-work`.

## Requirements

dude requires [Superpowers](https://github.com/obra/superpowers#installation). Install it first, in the same runtime you are installing dude into. dude's skills name Superpowers procedures and neither ship nor reimplement them, so those calls have nowhere to go until Superpowers is present.

## Install

OpenCode:

```json
{
  "plugin": ["dude@git+https://github.com/yowcow/dude.git"]
}
```

Add the entry to the `plugin` array in the global
`~/.config/opencode/opencode.json`, then restart OpenCode.

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

| Runtime | Requires `version`? | Uses it to decide an update? |
| --- | --- | --- |
| OpenCode | yes | no, git-backed installs do not use it to decide an update |
| Claude Code | no — `validate` only warns | **yes — a version left in place stops updates** |
| Codex | yes, strict semver | no |

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
model is cheap. Effort is not split the same
way: on Claude Code a worker runs at the session's effort, so launch even a cheap
session at the effort you want its marked workers to have. Whether a cheap main loop still
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

| Runtime | `using-dude` in context at session start? | How to reach it by hand |
| --- | --- | --- |
| OpenCode | yes — `messages.transform` on the first user message | — |
| Claude Code | yes — a SessionStart hook | — |
| Codex | yes, once the hook is trusted | `dude:using-dude` |

Each row's evidence is in the prose below.

OpenCode's package plugin registers all nine skills and prepends `using-dude`
to the first user message through `experimental.chat.messages.transform`, so
it is in context at session start. The injected text uses a dude-only marker
and does not contain `EXTREMELY_IMPORTANT`, so Superpowers' bootstrap and
this one do not skip each other. Two loads of the same plugin (a global git
install plus the checkout's `.opencode/plugins/`) still inject once.

Claude Code needs no invocation: a SessionStart hook puts `using-dude` in context
at the start of every session.

Codex installs all nine skills and runs `hooks/hooks.json` once the hook is
trusted, so `using-dude` is in context there too — the Install section above
covers what trust involves. The `dude:using-dude` skill works whether the hook is
trusted or not.

The skill bodies use bare names (`plan-work`), because the `dude:` prefix is a
plugin namespace the host adds.

### What tier a marked worker runs at

`using-dude`'s **Worker tier** sends a worker whose miss would pass as "nothing
found" out at the highest tier the runtime can put on a worker, which the run's
own tier does not cap. Which tier that actually is gets
settled by a ladder rather than by the run alone: where the runtime carries a
default for subagents, a worker dispatched without a model of its own lands on
that default; where none is set, it falls back to the run's own tier. So raising
the run's own tier does not reach the marked worker on a machine whose subagent
default sits below it — the mark reads as satisfied while that worker runs a
tier under the session that dispatched it.

Measured on Claude Code 2.1.258, the two rungs have separate carriers. The
subagent default is the environment variable `CLAUDE_CODE_SUBAGENT_MODEL`; the
run's own model is the `model` key in `settings.json`, or `claude --model` at
launch. The first is carried by no settings key of its own, so the check goes to
the environment — the session's own rather than a bare login shell, since a
settings file's `env` block is documented as carrying variables too:

```
env | grep CLAUDE_CODE_SUBAGENT_MODEL
```

Output naming a model below the highest tier you have is the case where the mark
quietly loses, and this repository's own machine was measured in exactly that
state: `sonnet` there, exported from a shell profile, while `settings.json`
carried no subagent key whatsoever. Reading `settings.json`
alone is what makes such a default look absent.

What the dispatched worker then ran on has to be read back from its transcript
rather than asked of it — a self-report is the worker's own account rather than
the runtime's record of the call, and the environment it inherits can name a
model it is not running. Read that way here, a worker dispatched with no model
named ran on `claude-sonnet-5` while the session ran `claude-opus-5`; one
dispatched with `opus` named ran on `claude-opus-5`. Empty output from the check
means no default is set, and the fallback to the parent's model is then
documented behavior rather than something this repository has observed.

Close the gap at the default: set `CLAUDE_CODE_SUBAGENT_MODEL` to the highest
tier you have and leave it there whatever tier the run itself is on — a session
measured at a cheap tier dispatched workers a tier above itself throughout.
Setting it there is what makes the mark independent of the dispatch, and
dispatches do omit the model in practice: 5 of the pilot's 55 workers were
dispatched with none named, and in the one window measured alone that was 2 of
4, a marked reviewer among them
([measurements](https://github.com/yowcow/dude/issues/169#issuecomment-5535611330)).
It also reaches a worker that a worker dispatched, two levels down, which the
dispatching skill never sees. Naming the model at the dispatch was measured
working too, and remains right to do; it just has to be got right once per
dispatch, where the default is got right once.

The default knows nothing of which workers are marked, so every worker
dispatched without a model of its own rises with it, the unmarked ones and their
cost included, while the session stays where it is. A fork stays outside its
reach: it continues the parent's context and runs the parent's model by
construction, so a cheap session forks cheap however the default is set. It can
cost more per request than the session it came from, having inherited the
context at its largest
([measurements](https://github.com/yowcow/dude/issues/169#issuecomment-5535611330)).
dude's skills dispatch no forks, so this is a mechanism to recognize rather than
a hole in the flow.

On Claude Code, reasoning effort needs no ladder, because a worker runs at the session's effort.
Every worker across the pilot's four windows did, including workers running a
model the session was not — which is what rules out their having picked it up
from a per-model setting
([measurements](https://github.com/yowcow/dude/issues/169#issuecomment-5534943995)).
There is no lever here for spending less on the work you would rather run
cheaply, and a per-agent definition is not one: its `effort:` binds only where
a dispatch names that agent type, dude's dispatches do not, and the only route
left would be writing dude's own wiring into your instruction file — which
yowcow/dude#139 declined.

Prompt-cache TTL is a third setting, and it splits the main loop from its
workers by construction. Claude Code carries it as `promptCacheTtl` in
`settings.json`, whose own description scopes it to the main conversation, and
as `CLAUDE_CODE_PROMPT_CACHE_TTL` in the environment, which takes precedence;
both take `5m` or `1h`, and a `subagentPromptCacheTtl` sits beside it for
everything outside the main conversation. Measurement agrees with that scope:
the window set to `5m` wrote all of its main-loop cache at `5m`, while subagents
wrote at `5m` in every window — the pilot varied only the main-conversation
setting, so that is the reach of the finding rather than a property of
subagents. That it can be chosen at all corrects yowcow/dude#159's record of
it as fixed. Which way it moves cost is not settled — the cheaper write is
offset by having to write more often, and separating the two needs the same work
replayed
([measurements](https://github.com/yowcow/dude/issues/169#issuecomment-5534943995)).

All three were measured on Claude Code alone; what the other two runtimes do
with a subagent default, a session's effort, or a cache TTL has not been
measured here, which is not a claim that they have no tier lever. Where a
runtime turns out to have none, `using-dude`'s **Worker tier** leaves it
undecided by design — so leave the main loop's tier alone there, because a
marked worker with no rung above the session has nowhere to stand once the
session comes down.

### What the run's own tier decides

That ladder is about workers, and a review finding's verdict is on that side of
it. `implement-work` owns both of its gates and lets no worker declare either
clean. `pr-to-ready` never delegates the clean judgment or the stop
conditions, reading whether checks pass included. `simplify-code` dispatches
proposers and keeps in the main loop which of their proposals are accepted;
`review-code` and `review-plan` dispatch reviewers that return findings, and
there the main loop is what decides when the loop or the pass ends. Each of
those skills draws that line in its **Orchestration model**, and the three that
judge a review finding put that one judgment on the far side alike: in
`review-code`, `review-plan` and `pr-to-ready`, a finding's verdict goes out to
a marked worker and never runs in the main loop.

So the run's own tier is not only the fallback a worker dispatched without a
model of its own lands on. Lower it to spend less and every judgment on the
near side of those lines goes down at once, while the run keeps reporting
*clean* — what fell is the judgment rather than the shape of the output, so no
gate in the flow has anything to catch. Where that fallback is the one in
force, the far side comes down with it.

### What else the run's cost rides on

The same cheap main loop, measured in two windows, cost 2.4× per request
($0.1091 against $0.0452) once the session had grown: `cache_read` / request
372,916 against 153,951, over 3 hours 15 minutes against 22 minutes. The cheap-tier
saving is eaten by that growth; window 1 came back 5.7% under the lower end of
the band in yowcow/dude#161. In that longer window the workers carried 73.3% of
the $60.92 total. A worker request was cheaper than the main loop's ($0.0583
against $0.1091); the count is what dominated. Lowering the main loop's tier
does not reduce that share
([measurements](https://github.com/yowcow/dude/issues/169#issuecomment-5534943995);
[correction](https://github.com/yowcow/dude/issues/169#issuecomment-5535611330)).

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
all nine local skills.

Installing dude a second time under a throwaway name is not a way to try hook
changes out. Two installs run the `SessionStart` hook twice, and both blocks
reach the same session. Which tree each one came from is readable — the injected
text names the install path it ran from — but the session is still carrying
`using-dude` twice, counted twice against the context and in two versions that
disagree wherever the branch has moved. Read the rules from the older block and
the session was not checking the branch at all. Uninstalling the github-sourced
`dude@dude` first is what avoids that, and it rewrites somebody's plugin
environment — ask whoever owns it.

The hazard is the hook running twice, so it is not specific to Claude Code:
Codex runs `hooks/hooks.json` too, once the hook is trusted. Whether a second
Codex install injects twice as well has not been measured here.

Check the manifests before installing — the validators name the offending
field:

```
claude plugin validate .
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .
python3 -m json.tool .agents/plugins/marketplace.json >/dev/null
```

`claude plugin validate` starts from `.claude-plugin/marketplace.json` and reaches that same
`plugin.json` through the entry's `"source": "./"`, which is where its `No version
specified` warning comes from — expected here, per the Versions section above.
The Codex validator reads `.codex-plugin/plugin.json` and walks every `SKILL.md`
as well, so it catches malformed frontmatter at the same time. Neither manifest
validator named above looks at
`.agents/plugins/marketplace.json` — each still passes with that file
deliberately corrupted — so `python3 -m json.tool` is what covers it, syntax
only. `make lint test` checks none of them: it covers shell and the test suite.

`AUTHORING.md` holds the rules for writing and editing these skills — where
each kind of text belongs, and the deletion test every sentence has to pass.

## License

MIT. See `LICENSE`.
