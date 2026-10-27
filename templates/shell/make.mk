# templates/shell: copy to .config/make/shell.mk, `include` it after base.mk.
# lefthook hands the changed paths; these run over the whole tree. shfmt walks
# `.`; shellcheck cannot, so bash's globstar does - dotglob, since a lane's file
# can sit under `.config/`.
check::
	shfmt -i 0 -ci -d .
	@shopt -s globstar nullglob dotglob; set -- **/*.sh; if (($$#)); then shellcheck -x "$$@"; fi

fmt::
	shfmt -i 0 -ci -w .
