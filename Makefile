# repokit - templates a repo copies.
# This repo is its own first consumer: base.mk is included from templates/,
# not copied.
include templates/base/make.mk
include templates/shell/make.mk

# base.mk defines `deps` first; `help` stays the default.
.DEFAULT_GOAL := help

.PHONY: help test

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

# Prettier: this repo's docs formatter, not shipped. check/fmt are base.mk's;
# this appends. The pattern is quoted: prettier expands it, not sh.
check::
	prettier --check '**/*.{md,json,yml,yaml}'

fmt::
	prettier --write '**/*.{md,json,yml,yaml}'

# scripts/{release,notes,publish}.sh still cut the grader's releases: they
# wait to become templates, with no target until then.
