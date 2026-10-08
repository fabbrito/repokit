// Fixture policy over templates/base's config. Deliberately tight: the
// harness proves the rules, so the numbers here are small enough to trip on
// purpose.
import base, { dirs } from '../../templates/base/commitlint.config.mjs';

export default {
  ...base,
  rules: {
    ...base.rules,
    'type-enum': [2, 'always', ['feat', 'fix', 'docs']],
    'scope-enum': [2, 'always', ['engine', 'conf', ...dirs('tests/commit-msg/roots')]],
    'header-max-length': [2, 'always', 40],
    'body-max-line-length': [2, 'always', 50],
  },
};
