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

| Template | mise                       | lefthook                                        | `make upgrade`       | Also                                                                                                               |
| -------- | -------------------------- | ----------------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `base`   | lefthook, node, commitlint | `commitlint`, `lefthook validate`, `make-phony` | mise's pins          | `commitlint.config.mjs`, `lefthook-rc.sh`, `make-phony.sh`, `make.mk` (`deps`, `hooks`, `check`, `fmt`, `upgrade`) |
| `shell`  | shfmt, shellcheck          | shfmt, shellcheck                               | —                    | flags in `.shellcheckrc`                                                                                           |
| `dprint` | dprint                     | dprint: md, json, toml, yaml                    | the plugins          | a starter `dprint.json`                                                                                            |
| `rust`   | cargo-cooldown             | cargo fmt, cargo check                          | `Cargo.lock`, cooled | `cooldown.toml`; Rust itself by `rust-toolchain.toml`                                                              |
| `ts`     | bun                        | oxfmt, oxlint, typecheck                        | —                    | tools pinned by `bun.lock`                                                                                         |

```
templates/<t>/mise.toml     → .config/mise/conf.d/<t>.toml
templates/<t>/lefthook.yml  → .config/lefthook/<t>.yml
templates/<t>/make.mk       → .config/make/<t>.mk
templates/base/lefthook-rc.sh → .config/lefthook-rc.sh
templates/base/make-phony.sh → .config/make-phony.sh
templates/base/commitlint.config.mjs → .config/commitlint.config.mjs
templates/rust/cooldown.toml → cooldown.toml     (the repo root)
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
# Makefile - base first, then one include per template
include .config/make/base.mk
include .config/make/shell.mk
.DEFAULT_GOAL := help # base.mk defines `deps` first
```

`make deps` installs the pinned tools (`mise install`); `make hooks`, once per clone, only the git
hooks. Bumping a tool is a version in `.config/mise/conf.d/<t>.toml` and `make deps` again. A repo
with more to install appends it as its own `deps::`, run after base's:

```make
deps::
	mise exec -- bun install # mise exec: PATH was read before mise install
```

A target documented with `## text` is a command: declare it `.PHONY`, or a directory of its name
makes it "up to date". `make-phony` refuses one that is not, in the hook and in `make check`.

`check` and `fmt` extend the same way: each template's `make.mk` appends its lanes, and so does a
repo's own. `$(call tree_files,'<pathspec>')` is base's whole-tree file set for a lane that takes
paths.

Moving from the `check`/`fix` lefthook groups: delete the Makefile's own `check:` / `fmt:` — a
single-colon rule beside base's `check::` is a make error — and `include` each `.config/make/<t>.mk`
after `base.mk`. A target depending on `check` keeps working.

## Hooks

Two scopes, same tools. lefthook is the git hooks only; the whole tree is make's, plain commands,
not `lefthook run`. A new lane goes in both: a template's `lefthook.yml` and its `make.mk`, a repo's
own `lefthook.yml` and Makefile.

| Where               | Files                                           | Formatters                          | Linters |
| ------------------- | ----------------------------------------------- | ----------------------------------- | ------- |
| `pre-commit` (hook) | the staged set                                  | write, and re-stage (`stage_fixed`) | check   |
| `make check`        | the whole tree, untracked included, ignored out | check                               | check   |
| `make fmt`          | same as `check`                                 | write, never stage                  | —       |

- **Pinned or nothing.** Git hooks never see `mise activate`. The `rc:` guard in `base` puts mise's
  tools on `PATH` before lefthook runs, and fails the hook when mise is missing — a hook that falls
  back to apt's shellcheck passes on the wrong version. `make.mk` does the same for targets. Typing
  `lefthook run` by hand bypasses both: use `make` or `mise exec --`.
- A whole-tree formatter — after its config changed, `cargo fmt --all` — checks on commit, never
  writes: `stage_fixed` re-stages staged paths only.
- Every job handed paths skips symlinks: a formatter handed one fails for the wrong reason.
- Partially staged files are safe: lefthook hides the unstaged half while jobs run.
- `LEFTHOOK=0` skips every hook. `lefthook run commit-msg <file>` grades a message by hand.
- In a recipe, the tool's plain name: `base.mk` already put mise's paths first. `mise exec` appends
  them, so a tool already on `PATH` wins over the pin - it is for a shell, or a recipe that runs
  before `make deps` has installed anything.

## Upgrade

`make upgrade` is `bump`, then `fmt` and `check`: nothing is formatted or checked until every bump
has run, and a bump that breaks the tree is caught before the diff is offered. `bump`'s first
prerequisite refuses a dirty tree, so the diff is only the bumps.

A bump is one tool's own updater, appended as a prerequisite of `bump` - `bump: bump-dprint` - so
the order is the order the files are included: base's, then each template's, then the repo's own.

| Template | bumps                                                |
| -------- | ---------------------------------------------------- |
| `base`   | mise's pins, `mise upgrade --bump --local`           |
| `dprint` | the plugins in `dprint.json`, `dprint config update` |
| `rust`   | `Cargo.lock`, through `cargo cooldown update`        |
| `ts`     | — (its tools are `bun.lock`'s)                       |

`--bump` because a pin is exact: nothing moves without it. `--local` because the global config's
tools are not this repo's. A major release is held either way - mise keeps the pin's precision,
`cargo update` stays inside the requirement - so widening one is a decision made by hand.

**A day of cooling, one place per tool.** A release younger than a day is held, not taken: `base`'s
`minimum_release_age` for mise, `--minimum-dependency-age P1D` for dprint, `cooldown.toml` for
cargo - which has no cooldown of its own until `min-publish-age` leaves nightly, so `rust`'s
`mise.toml` pins `cargo-cooldown` to apply it.

`Cargo.toml` keeps its floors and the lock is what moves: `cargo update` never rewrites a manifest.
`cargo upgrade` would move the floor too, and it picks by version rather than by publish date - it
dodges the cooldown, so it is not in the lane.

## Message rules

`.config/commitlint.config.mjs` extends `@commitlint/config-conventional`, which the CLI bundles: no
`package.json`. Its top is the repo's policy — `scope-enum` (fixed names plus `dirs('<root>')`, a
scope per directory, or `dirs('.', /^\d{4}$/)` for the ones a pattern picks out), `type-enum`, the
limits — then the two local rules:

- **`body-bullets`** — one blank line under the subject, then `- ` bullets and nothing else, back to
  back, one line each, at most its option (default 2). A trailer block may close the message, one
  blank line before it allowed: what git itself writes.
- **`scope-not-empty`** — `feat(): x` is refused. The parser reads empty parens as no scope at all,
  so `scope-enum` never sees it; the header still shows them.

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
