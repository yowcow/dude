import { fileURLToPath } from 'node:url';

const skillsDir = fileURLToPath(new URL('../../skills', import.meta.url));
const pluginRoot = fileURLToPath(new URL('../..', import.meta.url));
const MARKER = 'dude-bootstrap:using-dude';

function bootstrap() {
  return `<!-- ${MARKER} -->\ndude's workflow rules — summary stub (not the full ruleset) from the dude install at ${pluginRoot}:\n\nBefore any task, read the \`dude:using-dude\` skill and follow it. The full rules live in skills/using-dude/SKILL.md of this install; this stub is only a pointer.\n\nThe orchestrator owns control flow and drives every transition; a worker never declares a phase complete or advances the workflow. A sub-skill's trailing transition is cut — what runs next is the caller's decision, not the sub-skill's.`;
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
