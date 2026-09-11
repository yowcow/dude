# AGENTS.md

Multi-runtime AI-workflow plugin (OpenCode, Claude Code, Codex), not an application. Default branch is `master`. dude is unversioned: every runtime is meant to track this branch's HEAD.

Skill bodies, `AUTHORING.md`, and `README.md` stay English. Branches follow `<issue-number>-<slug>`.

## Checks

```
make lint test
make manifest
```

CI runs `lint`, `test`, and the fixed `manifest` merge gate on pushes and pull requests. `manifest-latest` runs only on pull requests and the weekly schedule; it is informational and not required for merging. `make lint test` does **not** validate plugin manifests.

- lint: `tests/lint.sh` — `bash -n` + ShellCheck, selected by shebang (not `*.sh`), so the extensionless stub `tests/lib/bin/gh` is included. `.shellcheckrc` disables only SC2016 (GraphQL `$vars` in single-quoted `gh` queries must not expand).
- test: `tests/run.sh` — offline; `gh` is stubbed and never reaches the network.
- one file: `tests/run.sh tests/<skill>/<name>_test.sh`
- RED against a pre-fix script: `SUT=/path/to/old.sh tests/run.sh <one-test-file>` (`SUT` refuses a missing, empty, or unreadable file, and refuses more than one test file).

`make manifest` runs the official validators below, each of which names the field it rejects. It also JSON-parses `.agents/plugins/marketplace.json`, `package.json`, and `hooks/hooks.json`, which the vendor validators do not cover:

```
claude plugin validate .
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .
python3 -m json.tool .agents/plugins/marketplace.json >/dev/null
```

`manifest-latest` resolves current vendor releases only to detect compatibility drift; a person investigates a failure, updates the fixed baseline if warranted, or intentionally leaves the baseline unchanged.

`claude plugin validate .` warning `No version specified` is expected. Do not add `version` to `.claude-plugin/plugin.json` or the marketplace plugin entry — Claude treats a pinned version as “already up to date”. `.codex-plugin/plugin.json` keeps `"version": "0.1.0"` and that value is never bumped.

Action SHAs in `.github/workflows/ci.yml` are pinned with `pinact run .github/workflows/ci.yml`.

## What ships

A plugin install distributes `skills/` plus hooks/manifests. `tests/` lives at the repo root so it does **not** ship. Never put tests inside a skill directory.

`skills/<skill>/scripts/<name>.sh` needs `tests/<skill>/<name>_test.sh` (subdirectories mirrored); there is no exemption path, and the gate is permanent. Test-writing contract: `tests/README.md`.

Skill scripts must run on bash 3.2 (`${x,,}` is out; use `tr`).

`.gitignore` drops `/.claude/`, `/.worktrees/`, and `/docs/superpowers/plans/` — do not commit those.

## Authoring

`AUTHORING.md` binds every file in this repository. Read it before editing a `SKILL.md`, script, test, or README sentence. Deletion test: keep a sentence only if omitting it causes a silent wrong result; a later gate catching the mistake, or the run stopping to ask a person, is not that.

Load-bearing bits an editor otherwise guesses wrong:

- `using-dude` owns workflow rules; other skills cite it by name. Do not copy it.
- A `SKILL.md` has **no command blocks**. Policy/procedure there; mechanism in `scripts/`; rationale in `references/` (a skill gets that directory only once the rationale is its own document). Frontmatter `description`: when to use it, nothing else.
- Name Superpowers procedures (`superpowers:…`); never reimplement them; never name the host runtime. Skill bodies use bare names (`plan-work`), not `dude:plan-work`.
- `hooks/session-start` must not grow a `jq` dependency (not guaranteed at install) and must not be rewritten to a heredoc (bash 5.3+ hangs there).
- Do not install a second copy of dude to try hook changes — both SessionStart hooks fire into the same session.

Issue numbers under `tests/` that look like `#171` refer to `yowcow/dotfiles`, not this tracker. Qualify cross-repo references (`owner/repo#N`).
