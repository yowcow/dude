#!/usr/bin/env bash
# Shape-only gate for the V2 port (yowcow/dude#494). The full V2 behavior
# suite (setup-driven skill + stub verification) is yowcow/dude#495; this
# file pins only the entrypoint shape so this PR stays green without
# pre-empting that suite.
#
# Offline: the `@opencode/plugin` specifier is stubbed at runtime via a
# `node:module` resolve hook written to tmpdir (real `define` is identity,
# so the stub is faithful for shape purposes). Nothing is installed and no
# new file is committed for this.
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

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

node --import "$tmpdir/hooks.mjs" --input-type=module - "$ROOT" <<'JS'
import assert from 'node:assert/strict';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.argv[2];
const mod = await import(pathToFileURL(path.join(root, '.opencode/plugins/dude.js')));
assert.ok(mod.default, 'V2 plugin must default-export a definition');
assert.equal(mod.default.id, 'dude');
assert.equal(typeof mod.default.setup, 'function');
JS

printf 'ok 1/1 opencode-plugin_test.sh (V2 shape; behavior suite: yowcow/dude#495)\n'
