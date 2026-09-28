# repokit

Templates a repo copies — tool pins, git hooks, make targets — and one versioned tool,
`commit-msg-lint`, the commit-message grader they call. Tools are [mise](https://mise.jdx.dev)'s,
hooks are [lefthook](https://lefthook.dev)'s. A template is copied, then owned: nothing ties the
copy back here.

Every rejection says what is wrong **and what to write instead**: the committer is usually an agent,
and prose rules in `AGENTS.md` drift while a tool that rejects does not.

```
$ git commit -m 'Add the dispatcher.'
commit-msg-lint: subject is not type(scope): subject
  got:   Add the dispatcher.
  write: feat(hooks): add the dispatcher

the shape:
  type(scope): subject

  - bullet
  Trailer: value

  types: feat fix refactor chore style docs build perf
```

## Use it

Needs mise. Copy `base`, then whichever others the repo needs, each file to where its header says:

| Template | mise                      | lefthook                               | Also                                  |
| -------- | ------------------------- | -------------------------------------- | ------------------------------------- |
| `base`   | lefthook, the grader      | `commit-msg-lint`, `lefthook validate` | `lefthook-rc.sh`, `make.mk` (`hooks`) |
| `shell`  | shfmt, shellcheck         | shfmt, shellcheck                      | flags in `.shellcheckrc`              |
| `dprint` | dprint                    | dprint: md, json, toml                 | a starter `dprint.json`               |
| `rust`   | — (`rust-toolchain.toml`) | cargo fmt, cargo check                 |                                       |
| `ts`     | bun                       | oxfmt, oxlint, typecheck               | tools pinned by `bun.lock`            |

```
templates/<t>/mise.toml     → .config/mise/conf.d/<t>.toml
templates/<t>/lefthook.yml  → .config/lefthook/<t>.yml
templates/base/lefthook-rc.sh → .config/lefthook-rc.sh
templates/base/make.mk      → .config/make/base.mk
commit-msg.conf.example     → .config/commit-msg.conf
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
.DEFAULT_GOAL := help # base.mk defines `hooks` first

check: ## the commit gate - run before committing
	lefthook run check
```

`make hooks` once per clone: `mise install`, then `lefthook install`. Bumping the grader is a
version in `.config/mise/conf.d/base.toml` and `make hooks` again.

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

## The grader

`commit-msg-lint <file>|-` grades a message; `-` reads stdin. `commit-msg-lint version` prints its
version and schema. It reads `.config/commit-msg.conf` from the repo root, or `COMMIT_MSG_CONF`.

Exit: `0` ok, `1` rejected, `2` usage, config, or a broken environment, including git itself
failing. `2` is distinct on purpose: none of those judged your commit, and a `1` invites
`--no-verify` when the real problem is the machine.

## Message rules

`type(scope): subject`, then an optional body, then optional trailers.

- **Subject** — `type` from `types`; `scope`, when present, from the allowlist; the text
  lowercase-first with no trailing period; the whole line at most `subject_max`.
- **Body** — one blank line, then `- ` bullets and nothing else: at most `bullet_max` of them, each
  one line of at most `body_cols`. A wrapped line is not a bullet, it is the bullet above it. One
  more blank line before the trailer block is allowed: that is what git itself writes.
- **Trailers** — the allowlist is `trailer_person` plus `trailer_reference`, and nothing else.
  Person keys take `Name <email>`, reference keys take one token. Once a trailer appears, only
  trailers may follow.
- **Scopes** — `scope_fixed`, plus the basename of every directory a `scope_root` glob finds. The
  full list prints only when the rejection is an unknown scope.

Not graded: anything git wrote (`Merge `, `Revert `, `fixup!`, `squash!`, `amend!`), and **every
message during a rebase** — a rebase replays messages it did not author, and failing them would make
this tool the reason you cannot rebase.

## Config

`commit-msg.conf.example` is the schema document: every key, its default, and what it does. It is
parsed on every message, so a typo is exit 2 — an unknown key, a second line for a key that does not
accumulate, a bad number, each naming the line.

`schema = 2` is the one cross-version guarantee. Absent means 1, the githooks format that carried
`[group]` lanes; those belong in `lefthook.yml` now, and the grader says so. A schema the grader
does not know is exit 2, naming both numbers and which side is stale.

## Versioning

Only the grader is versioned; a template is a copy. Three questions, in order — the first `yes` is
the bump:

- **Major** — must a consumer edit a file? A `commit-msg.conf` that parsed no longer parses, a
  command renamed or removed, an exit code that changes meaning.
- **Minor** — can a repo that was green go red with no edit? A new rejection, a widened one.
- **Patch** — neither.

Pre-1.0 the major row is empty: its cases land as a minor. `1.0.0` when the feature set is stable.

## Not here

No secret scanning, no CI, no staleness sweep: nothing notices a copied template drifting from
upstream, or a repo pinned to an old grader. A guard the templates cannot express — a vault check, a
secret scan — is a local job calling a script. The grader does not grow lanes.

## Hacking

```bash
make            # the targets
make hooks      # once per clone
make test       # the fixture harness
make check      # every lane over the whole tree, read only
make fmt        # the same lanes, writing
```

This repo is its own first consumer, without copies: `lefthook.yml` extends `templates/`, the
Makefile includes `templates/base/make.mk`, and `.config/` holds symlinks into `templates/`. The
grader on `PATH` is the tree's own `bin/`, never the released one. Prettier is this repo's docs
formatter and is not shipped.

Tests are plain bash: `tests/commit-msg/<name>.msg` next to `<name>.expect` holding the expected
exit code, and cases in `tests/run.sh` that copy templates into throwaway repos and commit through
them. `scripts/smoke.sh` installs a published release through mise and grades with it;
`make publish` runs it last.

MIT.
