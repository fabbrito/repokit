# templates/ts: copy to .config/make/ts.mk, `include` it after base.mk.
# lefthook.yml's lanes over the whole tree: oxfmt and oxlint read their own
# ignores, tsc the graph. No lint fix: oxlint --fix rewrites code.
check::
	bun oxfmt --check
	bun oxlint --deny-warnings
	bun --filter '*' typecheck

fmt::
	bun oxfmt

# The lock moves and package.json's floors with it, inside the declared range:
# --latest rewrites them, a decision by hand. The day is bunfig.toml's.
.PHONY: bump-bun

bump: bump-bun

bump-bun:
	bun update
