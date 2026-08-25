# dude

Yet another AI workflow.

dude packages the skills that carry a change from an issue to a pull request
whose CI passes and whose review is clean, and the skills that root-cause a
problem before any change is proposed. Merging is left to a person, and so is
everything that depends on it. They are written to wire into one another: each
names the next flow rather than absorbing it, and each has its own gate.

## Skills

| Skill | What it produces |
| --- | --- |
| `using-dude` | The workflow rules the other skills are wired by, in context every session |
| `plan-work` | An agreed design plus a numbered TODO list at PR granularity |
| `implement-work` | A pushed branch of verified commits, for one PR-sized task |
| `pr-to-ready` | A PR whose CI passes and whose review is clean |
| `review-plan` | Findings on a TODO list or an implementation plan |
| `review-code` | A diff, branch, or working tree reviewed, with no blocking finding left unresolved |
| `simplify-code` | Recently changed code simplified, behavior preserved |
| `investigate-performance` | An evidence-backed explanation of a performance shortfall |
| `investigate-anomaly` | A blameless findings report on a failure, incident, or drifting metric |

The change flow is `plan-work` → `implement-work` → `pr-to-ready`, entered at
whichever stage the work has actually reached. An investigation runs first
where the cause is unknown, and hands its findings to `plan-work`.

## Install

Claude Code:

```
/plugin marketplace add yowcow/dude
/plugin install dude@dude
```

Codex CLI:

```
codex plugin marketplace add yowcow/dude
codex plugin add dude@dude
```

Grok CLI:

```
grok plugin install yowcow/dude
```

Grok asks you to trust the plugin before installing it. Answer that prompt
yourself on a first install — trust is what lets a plugin run hooks. `--trust`
skips it, which is why the Development section below uses it on a clone you
already own.

## Use

In Claude Code the skills are namespaced by the plugin:

```
/dude:plan-work
/dude:implement-work
/dude:pr-to-ready
```

`using-dude` needs no invocation in Claude Code: a SessionStart hook puts it in
context at the start of every session. Codex and Grok both install all nine
skills and both place `hooks/hooks.json` in the install — `grok inspect --json`
lists it as a recognized hook — but neither was observed to run it, so
`using-dude` is not in context there. Grok's interactive mode is untested.

Invoke it by name instead: Codex namespaces it `dude:using-dude`, and Grok marks
it user-invocable, exposing each skill as a slash command named after it
(`/using-dude`).

This is why `using-dude` is a skill rather than plain Markdown: an agent with no
injection route still reaches it by name.

The skill bodies themselves use bare names (`plan-work`), because the `dude:`
prefix is a plugin namespace the host adds — Claude Code and Codex both do,
Grok exposes the bare name — and a body that hard-coded one host's prefix would
read wrongly on the others.

## Development

Point a marketplace at a local clone instead of the remote:

```
/plugin marketplace add ~/repos/dude
/plugin install dude@dude

codex plugin marketplace add ~/repos/dude
codex plugin add dude@dude

grok plugin install ~/repos/dude --trust
```

Check the manifests before installing — the validators name the offending
field:

```
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .
grok plugin validate .
python3 -m json.tool .agents/plugins/marketplace.json >/dev/null
```

The first two read the plugin manifests, and the Codex one walks every
`SKILL.md` as well, so it catches malformed frontmatter at the same time.
Neither looks at `.agents/plugins/marketplace.json` — both still pass with that
file deliberately corrupted — so the third line is what covers it, syntax only.
`make lint test` checks none of them: it covers shell and the test suite.

`AUTHORING.md` holds the rules for writing and editing these skills — where
each kind of text belongs, and the deletion test every sentence has to pass.

## License

MIT. See `LICENSE`.
