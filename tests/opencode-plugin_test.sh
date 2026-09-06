#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

node --input-type=module - "$ROOT" <<'JS'
import assert from 'node:assert/strict';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.argv[2];
const { DudePlugin } = await import(pathToFileURL(path.join(root, '.opencode/plugins/dude.js')));
const hooks = await DudePlugin();
const existing = path.join(root, 'existing-skills');
const config = { skills: { paths: [existing] } };

await hooks.config(config);
await hooks.config(config);

assert.deepEqual(config.skills.paths, [existing, path.join(root, 'skills')]);
JS

printf 'ok 1/1 opencode-plugin_test.sh\n'
