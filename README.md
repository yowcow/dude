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

Claude Code:

```
/plugin marketplace add yowcow/dude
/plugin install dude@dude
```

Gemini CLI:

```
gemini extensions install https://github.com/yowcow/dude
```

Codex CLI:

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
hook, trust it, or continue without trusting. Unlike Grok's and Gemini's
install-time prompts, Codex's hook trust decides whether injection happens at
all.

Grok CLI:

```
grok plugin install yowcow/dude
```

Grok asks you to trust the plugin before installing it. Answer that prompt
yourself on a first install — it is what lets the plugin be installed at all.
`--trust` skips it, which is why the Development section below uses it on a
clone you already own.

Gemini asks you to consent before installing any third-party extension, and adds
a second warning when the extension ships hooks, as dude does. Answer it yourself
on a first install, for the reason the prompt gives — Google does not vet what it
installs for you. `--consent` skips it, which is why the Development section
below uses it too. Without it a non-interactive run does not fail; it waits on
the prompt for as long as you let it.

Antigravity:

```
agy plugin import gemini
```

`agy plugin import gemini` takes what Gemini CLI already has, so dude has to be
installed there first — the `gemini extensions install` above. `agy plugin list`
then reports dude with `"source": "gemini-cli"` and `"components": ["skills",
"hooks"]`, and all nine skills land in `~/.gemini/config/plugins/dude/skills/`.
The hooks come across with them but do not run; the section below has what that
costs. Measured on agy 1.1.23.

## Versions

dude is not versioned. Every runtime is meant to carry the default branch's
latest commit, so there is no release to cut and nothing to bump. Which manifest
carries a `version` at all follows from what each runtime does with one:

| Runtime | Requires `version`? | Uses it to decide an update? |
| --- | --- | --- |
| Claude Code | no — `validate` only warns | **yes — a version left in place stops updates** |
| Codex | yes, strict semver | no |
| Gemini | yes | no, on the git install and link routes above |
| Grok | no | no |

So the two manifests Claude Code reads — `.claude-plugin/plugin.json` and the
plugin entry in `.claude-plugin/marketplace.json` — carry no `version`.
`claude plugin update dude@dude` compares commits instead, and the version it
reports is a short commit sha. An install made while those manifests still said
`0.1.0` moves onto sha-tracking at its first `claude plugin update`, so nobody
has to reinstall. `claude plugin validate .` warns that no version is specified;
that warning is the expected state here, not something to fix.

`.codex-plugin/plugin.json` and `gemini-extension.json` keep `"version": "0.1.0"`
because their validators reject a manifest without one — and **that value is
never bumped**, because neither runtime reads it to decide an update. Codex
installs the marketplace snapshot's root directory itself, with no per-version
cache in between. Gemini's git install compares the HEAD `git ls-remote` reports
against the local one; it is the local-path install, which this README does not
document as a route, that compares versions instead.

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
| Claude Code | yes — a SessionStart hook | — |
| Gemini CLI | yes — the `GEMINI.md` `@`-import | — |
| Codex | yes, once the hook is trusted | `dude:using-dude` |
| Grok | no | `/using-dude`, a copy in `~/.grok/AGENTS.md`, or `--rules` |
| Antigravity | no | ask for `using-dude` by name |

Each row's evidence is in the prose below.

`using-dude` needs no invocation in Claude Code: a SessionStart hook puts it in
context at the start of every session. Gemini needs none either, by a different
route: `gemini-extension.json` names `GEMINI.md` as the extension's context file,
and that file `@`-imports `skills/using-dude/SKILL.md` rather than repeating it.
The import was measured resolving in full — the assembled session context carries
the skill body through its last line, not a truncated preview — and all nine
skills resolve to the extension rather than to anything installed alongside it.

Codex installs all nine skills and runs `hooks/hooks.json` once the hook is
trusted, so `using-dude` is in context there too — the Install section above
covers what trust involves. Grok installs all nine skills and places
`hooks/hooks.json` in the install — `grok inspect --json` lists it as a
recognized hook — but was never observed to run it, in an interactive session or
headless, so `using-dude` is not in context there.

Gemini reads `hooks/hooks.json` too, and **does not run it — leave it that way.**
A Gemini lifecycle matcher is compared for equality, not as a pattern, so the
`startup|clear|compact` this repository ships never equals the `startup` Gemini
sends, and the hook stays inert. Measured against a control that fires: with a
bare `startup` matcher linked alongside, Gemini registered both hooks and
executed only the control's. Narrowing the matcher to `startup` to "fix" that
would break Gemini rather than help it, because Gemini does not hydrate
`${CLAUDE_PLUGIN_ROOT}` — the hook would run an empty path and fail. Gemini's
injection is the `GEMINI.md` route above and needs no hook.

Antigravity installs all nine skills — `agy plugin import gemini` carries the
hooks across too — and **parses the hook file, which it used to reject.** Its own
format takes each top-level key as a hook *name*, so dude's Claude Code `hooks`
wrapper is read as a hook named `hooks`, and each entry under it is validated as
a handler object. A handler must carry a `command`, which the `SessionStart`
group did not, so the file failed with `Failed to parse hooks for plugin dude:
invalid hook "hooks": command hook must specify 'command'` and was discarded
whole. That group now carries a no-op `"command": "true"`, which satisfies the
check; Claude Code ignores the extra key. The warning is gone — measured against
the installed superpowers as a positive control, since it still ships the shape
dude used to have: in the same session Antigravity logged the parse failure for
`superpowers` and none for `dude`. A run logging neither is one that never
reached the parse stage, and settles nothing either way.

`loaded 0 named hooks from 0 hooks.json file(s)` still appears — it is emitted
before any plugin is parsed and reads the same before and after, so it is no
measure of this. Whether the no-op is registered as a handler at all is
therefore unobserved; either way it does not run. The events Antigravity's
shipped documentation lists are `PreToolUse`, `PostToolUse`, `PreInvocation`,
`PostInvocation`, and `Stop`, and `SessionStart` is not among them — that is read
off the documented event list, not observed — and `true` would exit 0 with no
effect if it ever did run.

Parsing cleanly buys quiet logs, not injection. The `GEMINI.md` route does not
carry over, and dude ships no `plugins/<name>/rules/` directory, so
`using-dude` is still not in context there. What a session does carry is the
skill's *listing*: asked whether the rules were present, it quoted back the
`description` from `using-dude`'s frontmatter and no line of its body. The
parse result and the `loaded 0 named hooks` comparison were measured on agy
1.1.24 and the skill-listing finding on 1.1.23; the `PreToolUse`/`PostToolUse`/
`PostInvocation`/`Stop` event list is still read from the shipped
documentation rather than measured. `PreInvocation` and the `rules/` merging
behavior were measured directly for yowcow/dude#145, below.

Measured on agy 1.1.25: `PreInvocation` fires as documented — before the
model is called — with `invocationNum` resetting to `0` at the start of
each user turn and incrementing only across additional model calls
*within* that turn (a turn forcing a tool call produced two `PreInvocation`
fires in a row, `invocationNum` `0` then `1`). The handler's `cwd` is the
plugin root, and a `command` written relative to that root resolves
correctly — both held across all seven fires taken in one session. An
`ephemeralMessage` injected on the first fire reached the model in that
same turn, and the value was still recoverable a turn later — though that
persistence read is not conclusive on its own, since the model's own prior
reply already states the value and could be answering from its transcript
rather than from anything still injected. A `userMessage` injected the
same way also reached the model, and unlike the ephemeral one it rendered
as its own turn in the transcript, indistinguishable from something the
user had typed — that visibility is the concrete difference between the
two step types.

`rules/AGENTS.md` does load when placed at a plugin's root, and the full
body arrived head to tail. Whether an `@`-import inside
it avoids duplicating body text stayed inconclusive: the fixture's
`@./import-target.md` line came back with its relative path resolved to an
absolute one, but the referenced file's own content was never substituted in
its place — neither a working import nor a plain literal miss, so this
doesn't settle the question either way. `agy plugin import gemini` does
carry a `rules/` directory across as a real file, confirmed by placing one
in a throwaway Gemini-CLI extension and finding it land byte-for-byte inside
the imported plugin's own directory — even though the import manifest's
`components` field never lists `rules` among its tracked categories, so its
absence there is not a rejection. This only worked once the extension was
installed for real (`gemini extensions install`); a `link`-installed
extension gave `agy plugin import gemini` nothing to find.

What the other four runtimes do with a stray `rules/` directory: Claude
Code's `claude plugin validate` neither rejects it nor inspects it (a
manifest check, not a runtime probe); Grok's `plugin validate` and
`inspect --json` both omit it silently, no warning either way; Codex has no
non-interactive command to check with — `codex plugin` exposes only
`add`/`list`/`marketplace`/`remove`; and Gemini CLI's own runtime handling is
not measured, because this account can no longer authenticate to the
interactive CLI at all ("This client is no longer supported for Gemini Code
Assist for individuals... migrate to the Antigravity suite of products"),
independent of anything about `rules/`.

Given both paths reached the model, and `rules/`'s one advantage over
`PreInvocation` — avoiding duplicated body text — never came back as a
confirmed yes, `PreInvocation` is the path yowcow/dude#146 should implement:
it carries no duplication risk of its own (it can read `SKILL.md` fresh at
the point it fires), while `rules/` would plausibly still need the body
copied in, given its import mechanism showed no sign of resolving to actual
file content. `PreInvocation`'s own cost — it fires on every model call, not
once per session — still needs the once-per-session narrowing that issue
already calls for.

Where `using-dude` is not in context, it has to be reached by hand, and there
are three shapes of that. **Ask for it by name** — Grok exposes each skill as a
slash command named after it (`/using-dude`), and Codex namespaces skills
`dude:using-dude`, which works trusted hook or not. Antigravity needs no
syntax at all: asked to use the skill named `using-dude`, a session opened the
installed `SKILL.md` and quoted a line of the body back. This is why `using-dude`
is a skill rather than plain Markdown, and it is the route that needs no setup.
**Put the body where the runtime already looks** — `grok inspect --json`, run
outside any project, reports `~/.grok/AGENTS.md` with `"scope": "global"`, and a
headless session started outside any project quoted a line of that file back, so
what it holds reaches the session and not just the inspector. That distinction is
the one the hook above fails: `grok inspect` lists the hook too. Put a copy of
`skills/using-dude/SKILL.md` there and the rules arrive with it — a copy, because
`AGENTS.md` has no import mechanism to point at the installed skill instead, and
a copy goes stale when the skill moves on. **Or pass it at launch** —
`grok --help` documents `--rules <RULES>` as "Extra rules to append to the system
prompt", so handing it the skill body appends the rules for that session. The
first two were measured here; the third is the flag's documented behavior, which
this repository has not observed.

The skill bodies themselves use bare names (`plan-work`), because the `dude:`
prefix is a plugin namespace the host adds — Claude Code and Codex both do,
while Gemini and Grok expose the bare name — and a body that hard-coded one
host's prefix would read wrongly on the others.

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

Output naming a model below the run's own is the case where the mark quietly
loses, and this repository's own machine was measured in exactly that state:
`sonnet` there, exported from a shell profile, against `opus` for the run, while
`settings.json` carried no subagent key whatsoever. Reading `settings.json`
alone is what makes such a default look absent.

What the dispatched worker then ran on has to be read back from its transcript
rather than asked of it — a self-report is the worker's own account rather than
the runtime's record of the call, and the environment it inherits can name a
model it is not running. Read that way here, a worker dispatched with no model
named ran on `claude-sonnet-5` while the session ran `claude-opus-5`; one
dispatched with `opus` named ran on `claude-opus-5`. Empty output from the check
means no default is set, and the fallback to the parent's model is then
documented behavior rather than something this repository has observed.

Two ways to close the gap, and the check above says which one is yours. Where it
named a model below the run's own, that default is where the marked worker lands
unless its own dispatch named one: unset it, or raise it to the run's model. The
default knows nothing of which workers are marked, so every worker dispatched
without a model of its own rises with it — but none of them past the run's own
tier, and the session stays where it is. Where the check came back empty,
nothing stands between the worker and the run's own tier, so raising that tier
is the route that reaches it — and that one moves the ceiling itself, lifting
the session and every worker under it, the unmarked ones and their cost
included.

Only the model axis is recorded here. Whether a reasoning-effort setting reaches
a dispatched worker was not settled: a transcript records the thinking a worker
spent, which is consumption rather than the setting that allowed it. This ladder
was measured on Claude Code alone; what the other four runtimes do with a
subagent default has not been measured here, which is not a claim that they have
no tier lever.

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

## Development

Point a marketplace at a local clone instead of the remote:

```
/plugin marketplace add ~/repos/dude
/plugin install dude@dude

gemini extensions link --consent ~/repos/dude

codex plugin marketplace add ~/repos/dude
codex plugin add dude@dude

grok plugin install ~/repos/dude --trust
```

`gemini extensions link` tracks the clone rather than copying it, so an edit to a
skill shows up in the next Gemini session without reinstalling.

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
Codex install injects twice as well has not been measured here. Gemini is not
on this route at all — it does not run the hook.

Check the manifests before installing — the validators name the offending
field:

```
claude plugin validate .
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .
grok plugin validate .
gemini extensions validate .
python3 -m json.tool .agents/plugins/marketplace.json >/dev/null
```

`grok plugin validate` reads `.claude-plugin/plugin.json`. `claude plugin
validate` starts from `.claude-plugin/marketplace.json` and reaches that same
`plugin.json` through the entry's `"source": "./"`, which is where its `No version
specified` warning comes from — expected here, per the Versions section above.
The Codex validator reads `.codex-plugin/plugin.json` and walks every `SKILL.md`
as well, so it catches malformed frontmatter at the same time. `gemini extensions
validate` reads `gemini-extension.json` only, and what it checks there is narrow
— that `version` parses as semver, and that the file `contextFileName` names
exists. Point that key at a file that is not there and it names the missing file;
it will not tell you the context file is empty, or that an `@` import inside it
went nowhere. None of the manifest validators named above looks at
`.agents/plugins/marketplace.json` — each still passes with that file
deliberately corrupted — so `python3 -m json.tool` is what covers it, syntax
only. `make lint test` checks none of them: it covers shell and the test suite.

`AUTHORING.md` holds the rules for writing and editing these skills — where
each kind of text belongs, and the deletion test every sentence has to pass.

## License

MIT. See `LICENSE`.
