# repokit — how to work here

Templates in `templates/<t>/` that a repo copies. Commit messages are commitlint's, with one local
rule, `body-bullets`, in `templates/base/commitlint.config.mjs`. The README is the consumer guide —
this file is how to change the thing.

**Write terse.** Fewest words that carry the fact: prose, comments, commits, this file.

## The invariant

A template is copied, then owned. Nothing ties a copy back here, so a template must stand alone: its
header says where it goes, and it works with only `base` beside it.

Per-repo behaviour is the consumer's own job or a tool's own config (`.shellcheckrc`) — never a
redefined template job: an extended job wins over a local one with the same name.

Built-in commitlint rules first. A local rule only for what none can express — today, the bullet
body.

This repo is its own first consumer, without copies: `lefthook.yml` extends `templates/`, the
Makefile includes `templates/base/make.mk`, `.config/` is symlinks into `templates/`. Never replace
a symlink with a copy. `.config/commitlint.config.mjs` imports `base`'s in place: every commit here
goes through the rule it ships.

## Errors are the product

- Every `body-bullets` rejection says what is wrong **and what to write instead**. Only the first
  half is an unfinished feature. Built-in rules say only the first; `helpUrl` covers the rest.
- Every rule is an error or off: the hook runs `--strict`, which fails a warning.
- Aggregate: grade the whole message. One pass, everything to fix.

## Templates

- Every `lefthook.yml` splits jobs across `pre-commit` (formatters write + `stage_fixed`, linters
  check), `check` (read only, working changes + untracked) and `fix` (writes, never stages). Keep
  the three in step with YAML anchors; `case_templates_keep_the_split` enforces it.
- A job handed paths carries `file_types: [not symlink]`. A whole-tree formatter checks on commit,
  never writes.
- Every tool a template runs is pinned in its `mise.toml`, or by the language's own pin
  (`rust-toolchain.toml`, `bun.lock`). No fallback to a system copy.

## Shell

- [YSAP style](https://style.ysap.sh), bash 4.4+, `shfmt -i 0 -ci`, `shellcheck -x`,
  `set -uo pipefail` with explicit checks. No `set -e`.
- A regex with a bracket class goes in a variable: inline, `[[:space:]]` reads as the closing `]]`
  to more than one parser, `shfmt` included.

## Tests

- Test our code and our composition, not lefthook's or mise's mechanics.
- Every `body-bullets` case gets a `.msg` + `.expect` in `tests/commit-msg/`. `base` and `shell` get
  cases in `tests/run.sh` that copy them into a throwaway repo and commit through it; every template
  gets the structural split check. Their tools' own behaviour is theirs to test.
- `make test`, never bare `tests/run.sh`: make puts mise's pinned tools on `PATH`.
- bats only when the harness outgrows itself.

## Commits

- Every commit lands green: lefthook's `pre-commit` runs the templates over the staged set.
  `make check` runs the same lanes over the whole tree. Never bare `lefthook run` — `make` or
  `mise exec --`.
- `type(scope): subject`, scope from `.config/commitlint.config.mjs`. The hook owns the shape — do
  not restate it here.
- AI co-authored: `Co-Authored-By:` naming the model. Never a session link.

## Scope

Omissions are deliberate and listed under **Not here** in the README. Bring the trigger, not the
feature.
