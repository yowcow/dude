import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const skillsDir = fileURLToPath(new URL('../../skills', import.meta.url));
const skillFile = fileURLToPath(new URL('../../skills/using-dude/SKILL.md', import.meta.url));
const MARKER = 'dude-bootstrap:using-dude';

let cached;

function bootstrap() {
  if (cached !== undefined) return cached;
  let body;
  try {
    body = readFileSync(skillFile, 'utf8').replace(/^---\n[\s\S]*?\n---\n/, '');
  } catch {
    body = `Error reading the using-dude skill at ${skillFile}. dude's workflow rules are NOT in context; read the file yourself before starting any task.`;
  }
  cached = `<!-- ${MARKER} -->\nThe using-dude skill is already in context. Do not load it again.\n\n${body}`;
  return cached;
}

export const DudePlugin = async () => ({
  config: async (config) => {
    config.skills ??= {};
    config.skills.paths ??= [];
    if (!config.skills.paths.includes(skillsDir)) config.skills.paths.push(skillsDir);
  },
  'experimental.chat.messages.transform': async (_input, output) => {
    if (!output.messages.length) return;
    const firstUser = output.messages.find((m) => m.info.role === 'user');
    if (!firstUser || !firstUser.parts.length) return;
    if (firstUser.parts.some((p) => p.type === 'text' && p.text.includes(MARKER))) return;
    const ref = firstUser.parts[0];
    firstUser.parts.unshift({ ...ref, type: 'text', text: bootstrap() });
  },
});
