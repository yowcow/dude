# dude

Yet another AI workflow.

dude packages the skills that carry a change from an issue to a merged pull
request, and the skills that root-cause a problem before any change is
proposed. They are written to wire into one another: each names the next
flow rather than absorbing it, and each has its own gate.

## Skills

| Skill | What it produces |
| --- | --- |
| `plan-work` | An agreed design plus a numbered TODO list at PR granularity |
| `implement-work` | A pushed branch of verified commits, for one PR-sized task |
| `pr-to-ready` | A PR whose CI passes and whose review is clean |
| `review-plan` | Findings on a TODO list or an implementation plan |
| `review-code` | A diff, branch, or working tree reviewed and its findings fixed |
| `simplify-code` | Recently changed code simplified, behavior preserved |
| `investigate-performance` | An evidence-backed explanation of a performance shortfall |
| `investigate-anomaly` | A blameless findings report on a failure, incident, or drifting metric |

The change flow is `plan-work` → `implement-work` → `pr-to-ready`, entered at
whichever stage the work has actually reached. An investigation runs first
where the cause is unknown, and hands its findings to `plan-work`.

## Install

```
/plugin marketplace add yowcow/dude
/plugin install dude@dude
```

## Use

In Claude Code the skills are namespaced by the plugin:

```
/dude:plan-work
/dude:implement-work
/dude:pr-to-ready
```

The skill bodies themselves use bare names (`plan-work`), because the `dude:`
prefix is Claude Code's plugin namespace and other agents install these as
plain skills with no prefix.

## Development

Point a marketplace at a local clone instead of the remote:

```
/plugin marketplace add ~/repos/dude
/plugin install dude@dude
```

`AUTHORING.md` holds the rules for writing and editing these skills — where
each kind of text belongs, and the deletion test every sentence has to pass.

## License

MIT. See `LICENSE`.
