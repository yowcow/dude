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
merge it — that issue plus two prompts, across two kinds of session:

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
   /dude:implement-work <sub-issue-url> dude:pr-to-ready (ready-on-clean=yes)
   ```

   The first flow takes the item to a draft PR on a pushed branch of verified
   commits; the second loops on CI and review until both are clean.

Then wait for the PR.

Only the first name on that last line is a slash command: Claude Code passes
everything after it to the skill as free text.

That is what makes the trailing `dude:pr-to-ready` a hand-off you perform
yourself, up front — `implement-work` ends by *naming* the next flow rather than
invoking it, because which flow runs next is the caller's decision rather than
the skill's. `ready-on-clean=yes` answers in the same breath the one question
`pr-to-ready` would otherwise stop and ask: whether a clean run should mark the
PR ready.

Neither is a parsed flag; the argument text is read rather than matched against a
grammar, and it is Claude Code's pass-through that was measured, not the other
runtimes'.

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
hooks across too — and then rejects the hook file: it logs `Failed to parse hooks
for plugin dude: invalid hook "hooks": command hook must specify 'command'`, and
`loaded 0 named hooks from 0 hooks.json file(s)`. Its own format takes each
top-level key as a hook *name*, where dude's file has Claude Code's single
`hooks` wrapper, and the events its shipped documentation lists are `PreToolUse`,
`PostToolUse`, `PreInvocation`, `PostInvocation`, and `Stop` — `SessionStart` is
not among them. The `GEMINI.md` route does not carry over either: Antigravity's
shipped documentation has it merging a plugin's rules from
`plugins/<name>/rules/`, and dude ships no such directory. So `using-dude` is not
in context there. What a session does carry is the skill's *listing*: asked
whether the rules were present, it quoted back the `description` from
`using-dude`'s frontmatter and no line of its body. Measured on agy 1.1.23.

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
