import { Plugin } from '@opencode/plugin';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const pluginRoot = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
const skillsRoot = path.join(pluginRoot, 'skills');
const MARKER = 'dude-bootstrap:using-dude';

// The same replacement hooks/session-start makes with `tr -c`: everything
// outside [A-Za-z0-9._/-] becomes `?`, byte for byte. Byte-wise rather than per
// code point so both emitters' install lines read alike for a non-ASCII path.
const ALLOWED_BYTE = (b) =>
  (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a) ||
  b === 0x2e || b === 0x5f || b === 0x2d || b === 0x2f;

function sanitizePath(p) {
  let out = '';
  for (const b of Buffer.from(p, 'utf8')) out += ALLOWED_BYTE(b) ? String.fromCharCode(b) : '?';
  return out;
}

function installValue(p) {
  const s = sanitizePath(p);
  return s.length > 100 ? `...${s.slice(-100)}` : s;
}

// POSIX cksum, the number the hook prints: CRC-32 (polynomial 0x04c11db7, MSB
// first, initial 0) over the bytes, the byte length appended base-256 least
// significant first, complemented, in decimal. One install path spelling, one
// number, on both emitters -- which is why the same rule is implemented twice.
// The spelling can differ: this side sees a non-UTF-8 name as U+FFFD and a
// symlinked one as the physical root, so the two numbers can differ with it.
function cksum(s) {
  const bytes = Buffer.from(s, 'utf8');
  let crc = 0;
  const feed = (b) => {
    crc = (crc ^ (b << 24)) >>> 0;
    for (let i = 0; i < 8; i += 1) {
      crc = ((crc & 0x80000000) ? ((crc << 1) ^ 0x04c11db7) : (crc << 1)) >>> 0;
    }
  };
  for (const b of bytes) feed(b);
  for (let n = bytes.length; n > 0; n = Math.floor(n / 256)) feed(n & 0xff);
  return ((~crc) >>> 0).toString(10);
}

function bootstrap() {
  return `<!-- ${MARKER} -->\n<!-- dude-install: ${installValue(pluginRoot)} -->\ndude's workflow rules — summary stub (not the full ruleset) from the dude install with cksum ${cksum(pluginRoot)}:\n\nBefore any task, read the \`dude:using-dude\` skill and follow it. The full rules live in skills/using-dude/SKILL.md of this install; this stub is only a pointer.\n\nThe orchestrator owns control flow and drives every transition; a worker never declares a phase complete or advances the workflow. A sub-skill's trailing transition is cut — what runs next is the caller's decision, not the sub-skill's.`;
}

function parseFrontmatter(text) {
  const m = /^---\n([\s\S]*?)\n---\n?/.exec(text);
  const fields = {};
  if (m) {
    for (const line of m[1].split('\n')) {
      const fm = /^([A-Za-z]+):\s*(.*)$/.exec(line.trim());
      if (fm) fields[fm[1]] = fm[2];
    }
  }
  return fields;
}

function loadSkills() {
  const skills = [];
  for (const entry of readdirSync(skillsRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const id = entry.name;
    const skillPath = path.join(skillsRoot, id, 'SKILL.md');
    let content;
    try {
      content = readFileSync(skillPath, 'utf8');
    } catch {
      // One unreadable skill must not take the others -- or the bootstrap stub,
      // which setup() would never reach -- with it.
      continue;
    }
    const fields = parseFrontmatter(content);
    skills.push({
      id,
      name: fields.name || id,
      description: fields.description || '',
      path: skillPath,
      content,
    });
  }
  return skills;
}

export default {
  ...Plugin.define({
    id: 'dude',
    async setup(ctx) {
      const skills = loadSkills();
      await ctx.skill.transform((editor) => {
        for (const s of skills) editor.add(s);
      });
      await ctx.session.hook('context', (event) => {
        if (event.system.some((p) => typeof p.text === 'string' && p.text.includes(MARKER))) return;
        event.system.push({ type: 'text', text: bootstrap() });
      });
    },
  }),
  // V1 object form (OpenCode 1.18.29+): V1 calls server() and uses the
  // returned hooks; V2 reads id/setup() and ignores server().
  async server() {
    return {
      config: async (config) => {
        config.skills = config.skills || {};
        config.skills.paths = Array.isArray(config.skills.paths) ? config.skills.paths : [];
        if (!config.skills.paths.includes(skillsRoot)) {
          config.skills.paths.push(skillsRoot);
        }
      },
      'experimental.chat.system.transform': async (_input, output) => {
        if (output.system.some((s) => typeof s === 'string' && s.includes(MARKER))) return;
        output.system.push(bootstrap());
      },
    };
  },
};
