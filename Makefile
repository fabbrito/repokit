# repokit - templates a repo copies, and the commit-message grader they call.
# This repo is its own first consumer: base.mk is included from templates/,
# not copied.
include templates/base/make.mk

# base.mk defines `hooks` first; `help` stays the default.
.DEFAULT_GOAL := help

.PHONY: help test check fmt release publish

define HELP_AWK
BEGIN {
	FS = ":.*##"
	printf "\nUsage: make \033[1m<target>\033[0m\n"
}
/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }
/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }
endef
export HELP_AWK

##@ Setup
help: ## show this help
	@awk "$$HELP_AWK" $(MAKEFILE_LIST)

##@ Quality
test: ## the fixture harness - grader + templates through lefthook
	tests/run.sh

# The lanes live in lefthook.yml, which extends templates/.
check: ## the whole-tree gate - every lane, read only
	lefthook run check --all-files

fmt: ## the same lanes, writing - never stages
	lefthook run fix --all-files

##@ Release
# release.sh stamps VERSION into the grader, gates, commits, tags.
release: ## tag a release here, gated - VERSION=vX.Y.Z [DRY_RUN=1]
	scripts/release.sh $(if $(DRY_RUN),--dry-run) $(VERSION)

publish: ## push the tag and cut the GitHub release - [DRY_RUN=1]
	scripts/publish.sh $(if $(DRY_RUN),--dry-run)
