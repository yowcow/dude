import { fileURLToPath } from 'node:url';

const skillsDir = fileURLToPath(new URL('../../skills', import.meta.url));

export const DudePlugin = async () => ({
  config: async (config) => {
    config.skills ??= {};
    config.skills.paths ??= [];
    if (!config.skills.paths.includes(skillsDir)) config.skills.paths.push(skillsDir);
  },
});
