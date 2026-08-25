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

Grok asks to trust the plugin before installing it; `--trust` answers that up
front.

## Use

In Claude Code the skills are namespaced by the plugin:

```
/dude:plan-work
/dude:implement-work
/dude:pr-to-ready
```

`using-dude` needs no invocation in Claude Code: a SessionStart hook puts it in
context at the start of every session. Codex and Grok both install all nine
skills, and both read `hooks/hooks.json`, but neither was observed to run the
hook — so `using-dude` is not in context there. Invoke it by name and read it
directly: Codex namespaces it `dude:using-dude`, and Grok exposes it as the
slash command `/using-dude` (or `/dude:using-dude` to disambiguate).

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

Check the manifests before installing. A rejected manifest shows up in
`codex plugin list` only as a silent absence, where the validators name the
offending field:

```
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .
grok plugin validate .
```

The Codex validator walks every `SKILL.md` too, so it catches malformed
frontmatter at the same time. `make lint test` does not check these files:
it covers shell and the test suite only.

`AUTHORING.md` holds the rules for writing and editing these skills — where
each kind of text belongs, and the deletion test every sentence has to pass.

## License

MIT. See `LICENSE`.
