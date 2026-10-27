# templates/shell: copy to .config/make/shell.mk, `include` it after base.mk.
# lefthook.yml's lanes over every shell file. None, no run: shfmt handed no
# path reads stdin.
#
# The hooks' set over the whole tree - tracked and untracked, ignored out,
# symlinks and deleted paths skipped. A list, not `.`: shfmt's own walk does not
# read .gitignore. Words, not lines: a path with a space splits.
shell_files = $(shell git ls-files -co --exclude-standard -- '*.sh' | \
	while IFS= read -r f; do [[ -L $$f || ! -e $$f ]] || echo "$$f"; done)

check::
	$(if $(shell_files),shfmt -i 0 -ci -d $(shell_files))
	$(if $(shell_files),shellcheck -x $(shell_files))

fmt::
	$(if $(shell_files),shfmt -i 0 -ci -w $(shell_files))
