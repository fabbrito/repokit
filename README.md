# repokit

Templates a repo copies — tool pins, git hooks, make targets. Tools are
[mise](https://mise.jdx.dev)'s, hooks are [lefthook](https://lefthook.dev)'s, commit messages are
[commitlint](https://commitlint.js.org)'s. A template is copied, then owned: nothing ties the copy
back here.

The committer is usually an agent, and prose rules in `AGENTS.md` drift while a hook that rejects
does not. The one rule commitlint lacks, `body-bullets`, says what is wrong **and what to write
instead**:

```
$ git commit -F msg
✖   body is prose, not bullets (lines 3-4)
  write: - the hook rejected every wrapped line of this paragraph [body-bullets]
```

## Use it

Needs mise. Copy `base`, then whichever others the repo needs, each file to where its header says:

| Template | mise                       | lefthook                          | Also                                                                   |
| -------- | -------------------------- | --------------------------------- | ---------------------------------------------------------------------- |
| `base`   | lefthook, node, commitlint | `commitlint`, `lefthook validate` | `commitlint.config.mjs`, `lefthook-rc.sh`, `make.mk` (`deps`, `hooks`) |
| `shell`  | shfmt, shellcheck          | shfmt, shellcheck                 | flags in `.shellcheckrc`                                               |
| `dprint` | dprint                     | dprint: md, json, toml, yaml      | a starter `dprint.json`                                                |
| `rust`   | — (`rust-toolchain.toml`)  | cargo fmt, cargo check            |                                                                        |
| `ts`     | bun                        | oxfmt, oxlint, typecheck          | tools pinned by `bun.lock`                                             |

```
templates/<t>/mise.toml     → .config/mise/conf.d/<t>.toml
templates/<t>/lefthook.yml  → .config/lefthook/<t>.yml
templates/base/lefthook-rc.sh → .config/lefthook-rc.sh
templates/base/make.mk      → .config/make/base.mk
templates/base/commitlint.config.mjs → .config/commitlint.config.mjs
```

Then:

```yaml
# lefthook.yml
extends:
  - .config/lefthook/base.yml
  - .config/lefthook/shell.yml
# this repo's own jobs go here - never a name a template already uses: the extended job wins
```

```make
# Makefile - first line
include .config/make/base.mk
.DEFAULT_GOAL := help # base.mk defines `deps` first

check: ## the commit gate - run before committing
	lefthook run check
```

`make deps` installs the pinned tools (`mise install`); `make hooks`, once per clone, only the git
hooks. Bumping a tool is a version in `.config/mise/conf.d/<t>.toml` and `make deps` again. A repo
with more to install appends it as its own `deps::`, run after base's:

```make
deps::
	mise exec -- bun install # mise exec: PATH was read before mise install
```

## Hooks

Every template splits its jobs across three hooks, and a repo's own jobs should follow suit:

| Hook         | Files                                       | Formatters                          | Linters |
| ------------ | ------------------------------------------- | ----------------------------------- | ------- |
| `pre-commit` | the staged set                              | write, and re-stage (`stage_fixed`) | check   |
| `check`      | working changes vs HEAD, untracked included | check                               | check   |
| `fix`        | same as `check`                             | write, never stage                  | —       |

`--all-files` swaps the set for every tracked file: `lefthook run check --all-files` is the
whole-tree gate.

- **Pinned or nothing.** Git hooks never see `mise activate`. The `rc:` guard in `base` puts mise's
  tools on `PATH` before lefthook runs, and fails the hook when mise is missing — a hook that falls
  back to apt's shellcheck passes on the wrong version. `make.mk` does the same for targets. Typing
  `lefthook run` by hand bypasses both: use `make` or `mise exec --`.
- A whole-tree formatter — after its config changed, `cargo fmt --all` — checks on commit, never
  writes: `stage_fixed` re-stages staged paths only.
- Every job handed paths skips symlinks: a formatter handed one fails for the wrong reason.
- Partially staged files are safe: lefthook hides the unstaged half while jobs run.
- `LEFTHOOK=0` skips every hook. `lefthook run commit-msg <file>` grades a message by hand.

## Message rules

`.config/commitlint.config.mjs` extends `@commitlint/config-conventional`, which the CLI bundles: no
`package.json`. Its top is the repo's policy — `scope-enum` (fixed names plus `dirs('<root>')`, a
scope per directory), `type-enum`, the limits — then the one local rule:

- **`body-bullets`** — one blank line under the subject, then `- ` bullets and nothing else, back to
  back, one line each, at most its option (default 2). A trailer block may close the message, one
  blank line before it allowed: what git itself writes.

Every rule is an error or off: the hook runs `--strict`, which fails a warning too. Exit `0` ok, `3`
rejected, `1` commitlint itself failed (a broken config), `9` the config is missing.

Not graded: anything git wrote (`Merge `, `Revert `, `fixup!`, `squash!`, `amend!`), and **every
message during a rebase** — a rebase replays messages it did not author.

### From `commit-msg-lint`

The grader's releases stay up: a repo pinned to one keeps working until it moves. To move:

- `base.toml`: the `github:fabbrito/repokit` pin out, `node` and `npm:@commitlint/cli` in, then
  `make deps`.
- `.config/lefthook/base.yml` and `.config/commitlint.config.mjs` copied fresh from `base`.
- `commit-msg.conf` into the config's policy: `types` → `type-enum`, `scope_fixed` + `scope_root` →
  `scope-enum` with `dirs()`, `subject_max` → `header-max-length`, `body_cols` →
  `body-max-line-length`, `bullet_max` → `body-bullets`' option. Then delete it.
- The trailer allowlist has no successor: trailers are free.

## Not here

No secret scanning, no CI, no staleness sweep: nothing notices a copied template drifting from
upstream. A guard the templates cannot express — a vault check, a secret scan — is a local job
calling a script.

## Hacking

```bash
make            # the targets
make deps       # pinned tools; again after a bump
make hooks      # once per clone
make test       # the fixture harness
make check      # every lane over the whole tree, read only
make fmt        # the same lanes, writing
```

This repo is its own first consumer, without copies: `lefthook.yml` extends `templates/`, the
Makefile includes `templates/base/make.mk`, `.config/` holds symlinks into `templates/`, and
`.config/commitlint.config.mjs` imports `base`'s and sets this repo's policy. Prettier is this
repo's docs formatter and is not shipped. `scripts/{release,notes,publish}.sh` cut the old grader's
releases and wait to become templates.

Tests are plain bash: `tests/commit-msg/<name>.msg` next to `<name>.expect` holding the expected
exit code, graded under `tests/commit-msg/commitlint.config.mjs`, and cases in `tests/run.sh` that
copy templates into throwaway repos and commit through them.

MIT.
