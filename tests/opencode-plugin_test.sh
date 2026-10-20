#!/usr/bin/env bash
# V1+V2 dual-export suite for the opencode plugin (yowcow/dude#495).
#
# Offline: the `@opencode/plugin` specifier is stubbed at runtime via a
# `node:module` resolve hook written to tmpdir (real `define` is identity,
# so the stub is faithful for shape purposes). Nothing is installed and no
# new file is committed for this.
#
# RED knob is PLUGIN_UNDER_TEST=<mutant .js>; put the mutant two directories under
# the repo root (pluginRoot resolves from ../..), or loadSkills() fails on ENOENT.
# SUT does not apply (subject is a JS module).
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

PLUGIN_UNDER_TEST="${PLUGIN_UNDER_TEST:-"$ROOT/.opencode/plugins/dude.js"}"
if [ ! -f "$PLUGIN_UNDER_TEST" ] || [ ! -s "$PLUGIN_UNDER_TEST" ] || [ ! -r "$PLUGIN_UNDER_TEST" ]; then
  printf 'opencode-plugin_test.sh: PLUGIN_UNDER_TEST does not name a readable non-empty file: %s\n' "$PLUGIN_UNDER_TEST" >&2
  exit 1
fi

cat >"$tmpdir/stub.mjs" <<'JS'
export const Plugin = { define: (d) => d };
JS

cat >"$tmpdir/hooks.mjs" <<'JS'
import { register } from 'node:module';
register('./resolve-hook.mjs', import.meta.url);
JS

cat >"$tmpdir/resolve-hook.mjs" <<'JS'
export async function resolve(specifier, context, next) {
  if (specifier === '@opencode/plugin') {
    return { url: new URL('./stub.mjs', import.meta.url).href, shortCircuit: true };
  }
  return next(specifier, context);
}
JS

session_json="$("$ROOT/hooks/session-start")"

node --import "$tmpdir/hooks.mjs" --input-type=module - "$PLUGIN_UNDER_TEST" "$ROOT" "$session_json" <<'JS'
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const pluginPath = process.argv[2];
// Node resolves symlinks when importing, so the plugin's root (import.meta.url)
// is physical while hooks/session-start prints the logical one (`pwd -L`).
const root = realpathSync(process.argv[3]);
const mod = await import(pathToFileURL(pluginPath));
assert.ok(mod.default, 'V2 plugin must default-export a definition');
assert.equal(mod.default.id, 'dude');
assert.equal(typeof mod.default.setup, 'function');

const registered = [];
let transformCalls = 0;
const hookCalls = [];
const fakeCtx = {
  skill: {
    transform: async (cb) => {
      transformCalls += 1;
      const editor = { add: (s) => registered.push(s) };
      await cb(editor);
    },
  },
  session: {
    hook: async (name, fn) => { hookCalls.push({ name, fn }); },
  },
};
await mod.default.setup(fakeCtx);
assert.equal(transformCalls, 1, 'setup must register exactly one skill transform');
assert.equal(hookCalls.length, 1, 'setup must register exactly one session hook');
assert.equal(hookCalls[0].name, 'context');

const skillDirs = readdirSync(path.join(root, 'skills'), { withFileTypes: true })
  .filter((e) => e.isDirectory()).map((e) => e.name).sort();
assert.equal(registered.length, skillDirs.length, 'one Skill.Info per skills/ dir');
assert.deepStrictEqual(registered.map((s) => s.id).sort(), skillDirs);
for (const s of registered) {
  assert.ok(s.id && s.name && s.description && s.content,
    `Skill.Info ${s.id} must carry id/name/description/content`);
  assert.ok(path.isAbsolute(s.path), `Skill.Info ${s.id} path must be absolute`);
  assert.ok(s.path.endsWith(path.join('skills', s.id, 'SKILL.md')),
    `Skill.Info ${s.id} path must point at its SKILL.md`);
  const raw = readFileSync(s.path, 'utf8');
  assert.ok(raw.length > 0 && s.content === raw,
    `Skill.Info ${s.id} content must equal its SKILL.md bytes`);
}
const usingDude = registered.find((s) => s.id === 'using-dude');
assert.ok(usingDude, 'using-dude must be registered');
const fm = /^description:\s*(.*)$/m.exec(
  readFileSync(path.join(root, 'skills/using-dude/SKILL.md'), 'utf8'));
assert.ok(fm, 'using-dude SKILL.md must contain a description: frontmatter line');
assert.equal(usingDude.description, fm[1],
  'using-dude description must match SKILL.md frontmatter');

const MARKER = 'dude-bootstrap:using-dude';
const hookFn = hookCalls[0].fn;
assert.equal(typeof hookFn, 'function');

// Unmarked system gains exactly one text entry containing MARKER.
{
  const event = { system: [] };
  await hookFn(event);
  assert.equal(event.system.length, 1);
  assert.equal(event.system[0].type, 'text');
  assert.ok(event.system[0].text.includes(MARKER));
  // Second call on the same event is idempotent.
  await hookFn(event);
  assert.equal(event.system.length, 1, 'context hook must be idempotent');
}

// Pre-marked system is untouched.
{
  const event = { system: [{ type: 'text', text: `<!-- ${MARKER} --> already here` }] };
  await hookFn(event);
  assert.equal(event.system.length, 1, 'pre-marked system must be untouched');
  assert.ok(event.system[0].text.includes('already here'));
}

// Non-string entries do not crash the guard and still get the stub.
{
  const event = { system: [{ type: 'text' }, { type: 'text', text: 42 }] };
  await hookFn(event);
  assert.equal(event.system.length, 3);
  assert.ok(event.system[2].text.includes(MARKER));
}

const sessionContext = JSON.parse(process.argv[4]).hookSpecificOutput.additionalContext;
const freshEvent = { system: [] };
await hookFn(freshEvent);
const stubText = freshEvent.system[0].text;
// The two emitters' real install paths are replaced first, so text added
// between the path and the heading's terminator colon still reaches the
// comparison. Only session-start's truncated form for a root past 100 chars
// (`...<cksum>:<suffix>:`) cannot be spelled from the plugin side, so that
// form alone is matched heading-wide: `[^\n]*` cannot cross into the body's
// later `dude:using-dude` colon, so it stops at the terminator.
const roots = [...new Set([process.argv[3], root])];
const normalize = (s) => roots
  .reduce((out, r) => out.replaceAll(`${r}/`, '<ROOT>').replaceAll(r, '<ROOT>'), s)
  .replace(/from the dude install at \.\.\.[^\n]*:/g, 'from the dude install at <ROOT>:');
const normStub = normalize(stubText);
const normSession = normalize(sessionContext);
// The hook's <EXTREMELY_IMPORTANT> wrapper is the one envelope the plugin
// must not carry, so it is stripped from the hook side alone. Comparing the
// sentences whole is what catches a copy that drifts.
const stubSentences = (s) =>
  s.replace(/^<!-- dude-bootstrap:using-dude -->\n/, '');
const hookSentences = stubSentences(normSession)
  .replace(/^<EXTREMELY_IMPORTANT>\n/, '')
  .replace(/\n<\/EXTREMELY_IMPORTANT>$/, '');
assert.equal(stubSentences(normStub), hookSentences,
  'the four stub sentences must match between .opencode/plugins/dude.js and hooks/session-start');

// V1 object form (OpenCode 1.18.29+): the same default export carries server().
assert.equal(typeof mod.default.server, 'function',
  'dual export must carry V1 server()');
const v1 = await mod.default.server();
assert.equal(typeof v1.config, 'function',
  'V1 server() must return a config hook');
const v1sys = v1['experimental.chat.system.transform'];
assert.equal(typeof v1sys, 'function',
  'V1 server() must return a system transform');

// V1 skills registration appends the skills dir to config.skills.paths.
{
  const config = {};
  const skillsPath = path.join(root, 'skills');
  await v1.config(config);
  assert.ok(config.skills.paths.includes(skillsPath),
    'V1 config must register the skills dir');
  await v1.config(config);
  assert.equal(config.skills.paths.filter((p) => p === skillsPath).length, 1,
    'V1 config must not duplicate the skills dir');
}

// V1 system stub equals the V2 stub once normalized, and stays idempotent.
{
  const output = { system: [] };
  await v1sys({}, output);
  assert.equal(output.system.length, 1);
  assert.equal(normalize(output.system[0]), normStub,
    'V1 stub must equal the V2 stub');
  await v1sys({}, output);
  assert.equal(output.system.length, 1, 'V1 system transform must be idempotent');
}

// V1 pre-marked system is untouched.
{
  const output = { system: [`<!-- ${MARKER} --> already here`] };
  await v1sys({}, output);
  assert.equal(output.system.length, 1, 'V1 pre-marked system must be untouched');
  assert.ok(output.system[0].includes('already here'));
}

// V1 non-string entries do not crash the guard and still get the stub.
{
  const output = { system: [{ type: 'text' }, 42] };
  await v1sys({}, output);
  assert.equal(output.system.length, 3);
  assert.equal(normalize(output.system[2]), normStub);
}

// V1 config preserves existing keys and paths.
{
  const config = { top: 1, skills: { other: 1, paths: ['/other'] } };
  const skillsPath = path.join(root, 'skills');
  await v1.config(config);
  assert.ok(config.skills.paths.includes('/other'), 'V1 config must keep existing paths');
  assert.ok(config.skills.paths.includes(skillsPath), 'V1 config must register the skills dir');
  assert.equal(config.skills.other, 1, 'V1 config must keep existing skills keys');
  assert.equal(config.top, 1, 'V1 config must keep top-level keys');
}

// V1 config replaces a non-array paths value instead of crashing.
{
  const config = { skills: { paths: '/other' } };
  const skillsPath = path.join(root, 'skills');
  await v1.config(config);
  assert.deepStrictEqual(config.skills.paths, [skillsPath]);
}
JS

printf 'ok 1/1 opencode-plugin_test.sh (V1+V2 dual export; yowcow/dude#495)\n'
