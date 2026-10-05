import { Plugin } from '@opencode/plugin';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const pluginRoot = fileURLToPath(new URL('../..', import.meta.url));
const skillsRoot = path.join(pluginRoot, 'skills');
const MARKER = 'dude-bootstrap:using-dude';

function bootstrap() {
  return `<!-- ${MARKER} -->\ndude's workflow rules — summary stub (not the full ruleset) from the dude install at ${pluginRoot}:\n\nBefore any task, read the \`dude:using-dude\` skill and follow it. The full rules live in skills/using-dude/SKILL.md of this install; this stub is only a pointer.\n\nThe orchestrator owns control flow and drives every transition; a worker never declares a phase complete or advances the workflow. A sub-skill's trailing transition is cut — what runs next is the caller's decision, not the sub-skill's.`;
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
  return readdirSync(skillsRoot, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => {
      const id = e.name;
      const skillPath = path.join(skillsRoot, id, 'SKILL.md');
      const content = readFileSync(skillPath, 'utf8');
      const fields = parseFrontmatter(content);
      return {
        id,
        name: fields.name || id,
        description: fields.description || '',
        path: skillPath,
        content,
      };
    });
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
        config.skills.paths = config.skills.paths || [];
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
