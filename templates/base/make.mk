# templates/base: copy to .config/make/base.mk and `include` it first in the
# Makefile. mise's pinned tools first on PATH, so a target runs what the hooks
# run. No mise is an error, not a quiet fallback.
#
# Bash for every recipe and $(shell) after this line, a repo's own included:
# first in the Makefile is what makes that every one. Strict as a script:
# an unset variable or a failed pipe stage fails the recipe.
SHELL := /bin/bash
.SHELLFLAGS := -uo pipefail -c

ifeq ($(shell command -v mise),)
$(error mise not on PATH - https://mise.jdx.dev, then make deps)
endif
export PATH := $(shell mise bin-paths | paste -sd: -):$(PATH)

.PHONY: deps hooks

##@ Tools and hooks

# Once per clone, and after a bump in mise. Double-colon: a repo appends its
# own deps (collections, packages) as another `deps::`, run after this one,
# with no `##` - that would list deps twice. Plain `deps:` is a make error.
deps:: ## install the pinned tools
	mise install

# Once per clone, after make deps: hooks do not travel with the tree.
# core.hooksPath is unset first - a leftover would hide lefthook's hooks.
# mise exec, not PATH: PATH was read before make deps installed lefthook.
hooks: ## install lefthook's hooks for this clone
	@git config --unset core.hooksPath || true
	mise exec -- lefthook install
	@echo 'hooks enabled - skip one commit with LEFTHOOK=0'

##@ Gate

# The hooks grade the staged set; these, the whole tree. Plain commands, not
# `lefthook run`: a hook is for git. Double-colon like deps: each template's
# make.mk appends its lanes as another `check::` / `fmt::`, with no `##`.
.PHONY: check fmt

check:: ## every lane over the whole tree, read only
	lefthook validate
	.config/make-phony.sh

fmt:: ## the same lanes, writing - never stages
	@:

# tree_files,<pathspec>: the hooks' file set over the whole tree - tracked and
# untracked, ignored out, symlinks and deleted paths skipped. Words, not
# lines: a path with a space splits.
tree_files = $(shell git ls-files -co --exclude-standard -- $(1) | \
	while IFS= read -r f; do [[ -L $$f || ! -e $$f ]] || echo "$$f"; done)

##@ Upgrade

# A bump is one tool's own updater, appended as a prerequisite of `bump`:
# `bump: bump-dprint`. Prerequisites run in include order - base's guard and
# pins, then each template's, then the repo's own - and `upgrade` reaches fmt
# and check only once every bump has run.
.PHONY: upgrade bump upgrade-guard bump-mise

upgrade: bump fmt check ## bump every pin and dependency, then format and check

bump: upgrade-guard bump-mise

# --bump: the pins are exact, so nothing moves without it. --local: this repo's
# tools, never the global config's. The age is mise.toml's minimum_release_age.
bump-mise:
	mise upgrade --bump --local

# A bump is a commit's worth of diff nobody has read yet: start clean, so the
# diff is only the bumps. A red `check` leaves it uncommitted to look at.
upgrade-guard:
	@test -z "$$(git status --porcelain)" ||
		{ echo 'upgrade: the tree is dirty; commit first' >&2; exit 1; }
