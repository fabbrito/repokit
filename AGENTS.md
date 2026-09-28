# repokit — how to work here

Templates in `templates/<t>/` that a repo copies, and the one versioned tool they call:
`bin/commit-msg-lint.sh`, the commit-message grader, shipped as a bare release asset pinned in mise.
The README is the schema and the consumer guide — this file is how to change the thing.

**Write terse.** Fewest words that carry the fact: prose, comments, commits, this file.

## The invariant

A template is copied, then owned. Nothing ties a copy back here, so a template must stand alone: its
header says where it goes, and it works with only `base` beside it.

Per-repo behaviour is the consumer's own job or a tool's own config (`.shellcheckrc`) — never a
redefined template job: an extended job wins over a local one with the same name.

The grader grades messages and nothing else. It does not grow lanes.

This repo is its own first consumer, without copies: `lefthook.yml` extends `templates/`, the
Makefile includes `templates/base/make.mk`, `.config/` is symlinks into `templates/`. Never replace
a symlink with a copy. The grader on `PATH` is `bin/`, via `mise.toml`'s `[env]` — never the
released one: make and the hooks must grade a change before it ships. `make bump` moves only
`templates/base`'s pin.

## Errors are the product

- Every rejection says what is wrong **and what to write instead**. Only the first half is an
  unfinished feature.
- Grader: exit 2 for usage, config, or a broken environment (git failing, no repo); 1 only for a
  real rejection.
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
- Grader functions carry a `gh_` prefix.

## Tests

- Test our code and our composition, not lefthook's or mise's mechanics.
- Every message rule gets a `.msg` + `.expect` in `tests/commit-msg/`. `base` and `shell` get cases
  in `tests/run.sh` that copy them into a throwaway repo and commit through it; every template gets
  the structural split check. Their tools' own behaviour is theirs to test.
- `make test`, never bare `tests/run.sh`: make puts mise's pinned tools on `PATH`.
- `make test` green before `make release`. bats only when the harness outgrows itself.

## Commits

- Every commit lands green: lefthook's `pre-commit` runs the templates over the staged set.
  `make check` runs the same lanes over the whole tree. Never bare `lefthook run` — `make` or
  `mise exec --`.
- `type(scope): subject`, scope from `.config/commit-msg.conf`. The hook owns the shape and prints
  it on reject — do not restate it here.
- AI co-authored: `Co-Authored-By:` naming the model. Never a session link.

## Scope

Omissions are deliberate and listed under **Not here** in the README. Bring the trigger, not the
feature.
