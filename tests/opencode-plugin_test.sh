#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

node --input-type=module - "$ROOT" <<'JS'
import assert from 'node:assert/strict';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.argv[2];
const { DudePlugin } = await import(pathToFileURL(path.join(root, '.opencode/plugins/dude.js')));

const MARKER = 'dude-bootstrap:using-dude';

function makeOutput(text) {
  return {
    messages: [{
      info: { role: 'user' },
      parts: [{ type: 'text', text }],
    }],
  };
}

function injected(output) {
  return output.messages[0].parts.filter(
    (p) => p.type === 'text' && p.text.includes(MARKER),
  );
}

const hooks = await DudePlugin();
const existing = path.join(root, 'existing-skills');
const config = { skills: { paths: [existing] } };

await hooks.config(config);
await hooks.config(config);
assert.deepEqual(config.skills.paths, [existing, path.join(root, 'skills')]);

const transform = hooks['experimental.chat.messages.transform'];
assert.equal(typeof transform, 'function');

const first = makeOutput('hello');
await transform({}, first);
const parts = injected(first);
assert.equal(parts.length, 1);
assert.match(parts[0].text, /^<!-- dude-bootstrap:using-dude -->/);
assert.match(parts[0].text, /# Using dude/);
assert.match(parts[0].text, /Workflow selection/);
assert.doesNotMatch(parts[0].text, /EXTREMELY_IMPORTANT/);
assert.equal(first.messages[0].parts[1].text, 'hello');

await transform({}, first);
assert.equal(injected(first).length, 1);

const withSuperpowers = makeOutput('<EXTREMELY_IMPORTANT>\nYou have superpowers.\n</EXTREMELY_IMPORTANT>');
await transform({}, withSuperpowers);
assert.equal(injected(withSuperpowers).length, 1);
assert.equal(
  withSuperpowers.messages[0].parts.filter((p) => p.text.includes('EXTREMELY_IMPORTANT')).length,
  1,
);

const alreadyNamed = makeOutput('please load using-dude');
await transform({}, alreadyNamed);
assert.equal(injected(alreadyNamed).length, 1);

const hooks2 = await DudePlugin();
const shared = makeOutput('shared');
await transform({}, shared);
await hooks2['experimental.chat.messages.transform']({}, shared);
assert.equal(injected(shared).length, 1);
JS

printf 'ok 1/1 opencode-plugin_test.sh\n'
