# repokit - templates a repo copies.
# This repo is its own first consumer: base.mk is included from templates/,
# not copied.
include templates/base/make.mk

# base.mk defines `deps` first; `help` stays the default.
.DEFAULT_GOAL := help

.PHONY: help test check fmt

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
test: ## the fixture harness - body-bullets + templates through lefthook
	tests/run.sh

# The lanes live in lefthook.yml, which extends templates/.
check: ## the whole-tree gate - every lane, read only
	lefthook run check --all-files

fmt: ## the same lanes, writing - never stages
	lefthook run fix --all-files

# scripts/{release,notes,publish}.sh still cut the grader's releases: they
# wait to become templates, with no target until then.
