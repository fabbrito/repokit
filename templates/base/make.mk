# templates/base: copy to .config/make/base.mk, `include` it first - that is
# what makes Bash and -uo pipefail every recipe's, a repo's own included.
SHELL := /bin/bash
.SHELLFLAGS := -uo pipefail -c

ifeq ($(shell command -v mise),)
$(error mise not on PATH - https://mise.jdx.dev, then make deps)
endif
# Recursive: expanded per recipe, so a bump's pins reach `fmt` and `check`.
orig_path := $(PATH)
export PATH = $(shell mise bin-paths | paste -sd: -):$(orig_path)

.PHONY: deps hooks

##@ Tools and hooks

# Double-colon: a repo appends its own `deps::`, with no `##` - deps twice.
deps:: ## install the pinned tools
	mise install

# Hooks do not travel with the tree; mise exec, since make deps may not have run.
hooks: ## install lefthook's hooks for this clone
	@git config --unset core.hooksPath || true
	mise exec -- lefthook install
	@echo 'hooks enabled - skip one commit with LEFTHOOK=0'

##@ Gate

# The whole tree, plain commands, not `lefthook run`. Double-colon: lanes append.
.PHONY: check fmt

check:: ## every lane over the whole tree, read only
	lefthook validate
	.config/make-phony.sh

fmt:: ## the same lanes, writing - never stages
	@:

##@ Upgrade

# A bump is a prerequisite of `bump`: include order is run order.
.PHONY: upgrade bump upgrade-guard bump-mise

upgrade: bump fmt check ## bump every pin and dependency, then format and check

bump: upgrade-guard bump-mise

# --bump: a pin is exact. --local: not the global config's. prune: nothing uses
# the version it replaced now.
bump-mise:
	mise upgrade --bump --local
	mise prune -y -q

# The diff is the bumps: untracked files are in no diff. One line - a `test ... ||`
# alone is a syntax error, make giving each line its own shell.
upgrade-guard:
	@test -z "$$(git status --porcelain --untracked-files=no)" || \
		{ echo 'upgrade: the tree is dirty; commit first' >&2; exit 1; }
