#!/usr/bin/env bash
# V1+V2 dual-export suite for the opencode plugin (yowcow/dude#495).
#
# Offline: the `@opencode/plugin` specifier is stubbed at runtime via a
# `node:module` resolve hook written to tmpdir (real `define` is identity,
# so the stub is faithful for shape purposes). Nothing is installed and no
# new file is committed for this.
#
# RED knob is PLUGIN_UNDER_TEST=<mutant .js>; SUT does not apply (subject is a JS module).
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
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const pluginPath = process.argv[2];
const root = process.argv[3];
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
// To end-of-line, not to a colon: the truncated session-start form is
// `...<cksum>:<suffix>` and the stub body itself holds a later
// `dude:using-dude` colon, so a greedy `.*(?=:)` eats the `Before any task`
// sentence and a first-colon match leaves `:suffix` behind.
const normalize = (s) =>
  s.replace(/from the dude install at [^\n]*/g, 'from the dude install at <ROOT>');
const normStub = normalize(stubText);
const normSession = normalize(sessionContext);
for (const line of [
  'dude-bootstrap:using-dude',
  'Before any task, read the `dude:using-dude` skill and follow it.',
  "The orchestrator owns control flow and drives every transition",
]) {
  assert.ok(normStub.includes(line), `plugin stub must contain: ${line}`);
  assert.ok(normSession.includes(line), `session-start context must contain: ${line}`);
}
assert.ok(normSession.includes(normStub.split('\n')[1].slice(0, 40)),
  'session-start context must contain the stub body');

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
