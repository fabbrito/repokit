// repokit's own message policy over templates/base's config, imported in
// place: this repo commits through the rule it ships.
import base from '../templates/base/commitlint.config.mjs';

export default {
  ...base,
  rules: {
    ...base.rules,
    'type-enum': [2, 'always', ['feat', 'fix', 'refactor', 'chore', 'style', 'docs', 'build', 'perf', 'test']],
    'scope-enum': [2, 'always', ['templates', 'tests', 'make', 'docs', 'repo', 'release']],
  },
};
