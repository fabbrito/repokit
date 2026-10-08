#!/usr/bin/env bash
#
# The whole harness. Plain bash and fixtures; bats only if this outgrows
# itself.
#
#   tests/commit-msg/<name>.msg + <name>.expect   expected exit code
#   case_*                                        throwaway repos, built here
#
# lefthook's mechanics are lefthook's to test - stashing, chunking, globbing.
# These cases prove only what is ours: the body-bullets rule, and the templates - which
# job runs in which hook, which writes, which stages, the file set `check`
# and `fix` compute - copied into a throwaway repo the way a consumer would.
#
# No errexit: a failing case is the point, not a reason to stop.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# A git hook exports GIT_DIR, GIT_INDEX_FILE and friends. If this harness ever
# runs from inside one, they would point every `git -C <tmpdir>` back at the
# real repository. Drop them before touching git at all.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_NAMESPACE
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR

src=$PWD
tmproot=$(mktemp -d) || exit 1
trap 'rm -rf "$tmproot"' EXIT

passed=0
failed=0

green=''
red=''
reset=''
if [[ -t 1 ]]; then
	green=$'\033[0;32m'
	red=$'\033[0;31m'
	reset=$'\033[0m'
fi

ok() {
	printf '%sok%s   %s\n' "$green" "$reset" "$*"
	((passed++))
}

no() {
	printf '%sFAIL%s %s\n' "$red" "$reset" "$1"
	shift
	local line
	for line in "$@"; do
		printf '       %s\n' "$line"
	done
	((failed++))
}

want_exit() {
	local name=$1 want=$2 got=$3
	if ((want == got)); then
		ok "$name"
		return 0
	fi
	no "$name" "want exit $want, got $got"
	return 1
}

want_in() {
	local name=$1 needle=$2 haystack=$3
	if [[ $haystack == *"$needle"* ]]; then
		ok "$name"
		return 0
	fi
	no "$name" "missing: $needle" "output: $haystack"
	return 1
}

want_not_in() {
	local name=$1 needle=$2 haystack=$3
	if [[ $haystack != *"$needle"* ]]; then
		ok "$name"
		return 0
	fi
	no "$name" "unexpected: $needle" "output: $haystack"
	return 1
}

# ------------------------------------------------------------- commit-msg

# Grading is text in, exit code out - but the rebase check asks git, so it
# runs inside a repo. Its own, never this one: a rebase in progress here would
# otherwise pass every fixture.
fixture_repo=''
repo=''

make_fixture_repo() {
	fixture_repo=$(mktemp -d -p "$tmproot") || return 1
	git -C "$fixture_repo" init -q
	mkdir -p "$fixture_repo/tests"
	cp -r tests/commit-msg "$fixture_repo/tests/commit-msg"
}

# grade <name>: the fixture under tests/commit-msg's config. That config
# imports templates/base's, so it runs from $src; its scope roots resolve
# against the fixture repo it stands in.
grade() {
	(cd "$fixture_repo" &&
		commitlint --strict -g "$src/tests/commit-msg/commitlint.config.mjs" \
			--edit "$fixture_repo/tests/commit-msg/$1.msg" 2>&1)
}

run_commit_msg() {
	local msg want got name out
	for msg in tests/commit-msg/*.msg; do
		name=${msg##*/}
		name=${name%.msg}
		want=$(<"tests/commit-msg/$name.expect")
		out=$(grade "$name")
		got=$?
		want_exit "commit-msg/$name" "$want" "$got"
		# A rejection may speak; a pass must not.
		if ((want == 0)); then
			[[ -z $out ]] || no "commit-msg/$name passes silently" "$out"
		fi
	done
}

# body-bullets is ours: its rejections say what to write, not just what is
# wrong.
run_commit_msg_output() {
	local out
	out=$(grade bad-scope)
	want_in 'commit-msg/bad-scope names the scopes' 'alpha' "$out"

	# Wrapped prose is one rejection, not one per line.
	out=$(grade bad-prose-body)
	want_in 'commit-msg/bad-prose-body names the run' \
		'body is prose, not bullets (lines 3-5)' "$out"
	want_in 'commit-msg/bad-prose-body writes it as a bullet' \
		'write: - the hook rejected' "$out"

	# A wrapped bullet names the bullet and the wrap, so the fix is not
	# "prefix a dash" - which the next pass would reject as a third bullet.
	out=$(grade bad-wrapped-bullet)
	want_in 'commit-msg/bad-wrapped-bullet names the wrap' \
		'bullet wraps across lines 3-4' "$out"
	want_not_in 'commit-msg/bad-wrapped-bullet does not suggest a dash' \
		'write: -' "$out"

	out=$(grade bad-blank-between-trailers)
	want_in 'commit-msg/a stray trailer says where trailers go' \
		'one block at the end' "$out"

	# A rebase replays messages it did not author.
	mkdir -p "$fixture_repo/.git/rebase-merge"
	grade bad-shape >/dev/null 2>&1
	want_exit 'commit-msg/mid-rebase grades nothing' 0 $?
	rmdir "$fixture_repo/.git/rebase-merge"
}

# --------------------------------------------------------------- templates

# A consumer repo in $repo: the named templates copied where the README
# says, a lefthook.yml extending them, hooks installed. base always, and
# first. The rc guard is left out - it needs mise, and gets its own case.
mkconsumer() {
	local t list=''
	repo=$(mktemp -d -p "$tmproot") || return 1
	git -C "$repo" init -q
	git -C "$repo" config user.email 'test@example.com'
	git -C "$repo" config user.name 'test'
	mkdir -p "$repo/.config/lefthook"
	cp "$src/templates/base/commitlint.config.mjs" "$repo/.config/" || return 1
	for t in base "$@"; do
		[[ $t == base && -n $list ]] && continue
		cp "$src/templates/$t/lefthook.yml" "$repo/.config/lefthook/$t.yml" ||
			return 1
		list+="  - .config/lefthook/$t.yml"$'\n'
	done
	printf 'extends:\n%s' "$list" >"$repo/lefthook.yml"
	git -C "$repo" add -A
	LEFTHOOK=0 git -C "$repo" commit -qm 'feat: init' || return 1
	(cd "$repo" && lefthook install >/dev/null 2>&1)
}

commit() {
	(cd "$repo" && git commit -qm "$1" 2>&1)
}

lh() {
	(cd "$repo" && lefthook run "$@" 2>&1)
}

unformatted='#!/bin/bash\nif true;then echo hi;fi\n'
formatted='#!/bin/bash
if true; then echo hi; fi'

# base calls commitlint from PATH, with the copied config, on the message.
case_base_grades_the_message() {
	local out
	mkconsumer || return
	printf 'x\n' >"$repo/a.txt"
	git -C "$repo" add a.txt

	out=$(commit 'nope')
	want_exit 'base/a bad message is refused' 1 $?
	want_in 'base/the refusal is commitlint' '[type-empty]' "$out"

	commit 'feat(repo): add a' >/dev/null
	want_exit 'base/a good message commits' 0 $?
}

# `lefthook run` ignores an unknown key; base's validate job does not - and
# it watches the copied templates, not just lefthook.yml.
case_base_validate_refuses_a_typo() {
	mkconsumer shell || return
	printf 'pre-commit:\n  paralel: true\n' >>"$repo/.config/lefthook/shell.yml"
	git -C "$repo" add .config/lefthook/shell.yml
	commit 'feat: tune hooks' >/dev/null
	want_exit 'base/a typo in a copied template refuses the commit' 1 $?
}

# The generated hook sources the rc before it finds lefthook. No mise must
# fail the hook, never fall back to whatever else is on PATH.
case_base_rc_refuses_without_mise() {
	local out bin
	mkconsumer || return
	cp "$src/templates/base/lefthook-rc.sh" "$repo/.config/lefthook-rc.sh"
	# The hook needs git, sh and lefthook - and nothing named mise.
	bin=$(mktemp -d -p "$tmproot") || return
	ln -s "$(command -v lefthook)" "$bin/lefthook"
	printf 'x\n' >"$repo/a.txt"
	git -C "$repo" add -A
	out=$(cd "$repo" && PATH=$bin:/usr/bin:/bin git commit -qm 'feat: a' 2>&1)
	want_exit 'base/no mise refuses the commit' 1 $?
	want_in 'base/no mise says what to install' 'mise not on PATH' "$out"
}

# A repo appends its own deps as another `deps::`: base's tools install
# first, and `hooks` installs none. -n: the recipes, not a real install.
case_base_make_deps_extends() {
	local out
	mkconsumer || return
	mkdir -p "$repo/.config/make"
	cp "$src/templates/base/make.mk" "$repo/.config/make/base.mk"
	printf 'include .config/make/base.mk\ndeps::\n\techo repo-deps\n' \
		>"$repo/Makefile"

	out=$(make -C "$repo" -n --no-print-directory deps 2>&1)
	want_exit 'base/deps extends without a make error' 0 $?
	want_in 'base/deps installs the tools, then the repo' \
		$'mise install\necho repo-deps' "$out"

	out=$(make -C "$repo" -n --no-print-directory hooks 2>&1)
	want_not_in 'base/hooks installs no tools' 'mise install' "$out"
}

# shell's policy: a formatter writes on commit and re-stages.
case_shell_formats_and_restages() {
	mkconsumer shell || return
	printf %b "$unformatted" >"$repo/a.sh"
	git -C "$repo" add a.sh
	commit 'feat: add a' >/dev/null
	want_exit 'shell/an unformatted file still commits' 0 $?
	want_in 'shell/the commit ships it formatted' "$formatted" \
		"$(git -C "$repo" show HEAD:a.sh)"
}

# shell wires the linter into pre-commit as a check.
case_shell_shellcheck_refuses() {
	mkconsumer shell || return
	printf 'x=1\n' >"$repo/a.sh"
	git -C "$repo" add a.sh
	commit 'feat: add a' >/dev/null
	want_exit 'shell/a shellcheck finding refuses the commit' 1 $?
}

# The target would fail shellcheck, and is no .sh itself: only a lane handed
# the link could refuse this commit.
case_shell_symlink_skipped() {
	mkconsumer shell || return
	printf 'x=1\n' >"$repo/target"
	ln -s target "$repo/link.sh"
	git -C "$repo" add target link.sh
	commit 'feat: add a link' >/dev/null
	want_exit 'shell/a symlink never reaches a lane' 0 $?
}

# check: our file set - untracked included - and no job that writes.
case_shell_check_is_read_only() {
	mkconsumer shell || return
	printf %b "$unformatted" >"$repo/new.sh"
	lh check >/dev/null
	want_exit 'shell/check sees an untracked file' 1 $?
	want_not_in 'shell/check never writes' 'if true; then' \
		"$(<"$repo/new.sh")"
	want_exit 'shell/check never stages' 0 \
		"$(git -C "$repo" diff --cached --name-only | wc -l)"
}

# fix: writes, and no stage_fixed.
case_shell_fix_never_stages() {
	mkconsumer shell || return
	printf %b "$unformatted" >"$repo/new.sh"
	lh fix >/dev/null
	want_exit 'shell/fix exits 0' 0 $?
	want_in 'shell/fix writes' "$formatted" "$(<"$repo/new.sh")"
	want_exit 'shell/fix never stages' 0 \
		"$(git -C "$repo" diff --cached --name-only | wc -l)"
}

# No HEAD: `git diff HEAD` fails, and check must fall back, not pass.
case_shell_check_without_head() {
	mkconsumer shell || return
	rm -rf "$repo/.git"
	git -C "$repo" init -q
	(cd "$repo" && lefthook install >/dev/null 2>&1)
	printf %b "$unformatted" >"$repo/new.sh"
	lh check >/dev/null
	want_exit 'shell/check without HEAD still sees files' 1 $?
}

# The split every template promises, read off lefthook's merged config rather
# than run: dprint, rust and ts call tools this repo does not pin, and their
# lanes are those tools' business. What is ours is the shape.
#
#   - a job handed paths skips symlinks
#   - only pre-commit re-stages, and only a job handed the staged paths: a
#     whole-tree writer would leave the rest unstaged
#   - every check and fix job computes its own file set - without `files` it
#     would grade the staged set, which is not what check promises
#   - check mirrors pre-commit job for job, and fix only fixes what check checks
case_templates_keep_the_split() {
	local t json bad out
	for t in "$src"/templates/*/; do
		t=${t%/}
		t=${t##*/}
		# Loud, not `|| return`: a case that quietly returns proves nothing.
		if ! mkconsumer "$t"; then
			no "templates/$t: a consumer cannot be built from it"
			continue
		fi
		out=$(cd "$repo" && lefthook validate 2>&1)
		want_exit "templates/$t validates" 0 $?

		json=$(cd "$repo" && lefthook dump --format json 2>/dev/null)
		bad=$(jq -r '
			def jobs($h): (.[$h].jobs // [])[] | . + {hook: $h};
			[jobs("pre-commit"), jobs("check"), jobs("fix")][]
			| select(
				((.run | test("\\{(staged_)?files\\}")) and
					((.file_types // []) | index("not symlink") | not))
				or (.stage_fixed and
					(.hook != "pre-commit" or (.run | test("\\{staged_files\\}") | not)))
				or (.hook != "pre-commit" and .name != "lefthook-validate" and
					(.files // "" | length == 0))
			)
			| "\(.hook)/\(.name)"' <<<"$json")
		want_exit "templates/$t: every job keeps the split" 0 \
			"$(printf '%s' "$bad" | wc -w)"
		[[ -z $bad ]] || no "templates/$t: jobs off the split" "$bad"

		bad=$(jq -r '
			def names($h): [(.[$h].jobs // [])[].name] | sort;
			if names("pre-commit") != names("check") then "check != pre-commit"
			elif (names("fix") - names("check")) != [] then "fix outside check"
			else empty end' <<<"$json")
		want_exit "templates/$t: check mirrors pre-commit, fix within check" 0 \
			"$(printf '%s' "$bad" | wc -w)"
		[[ -z $bad ]] || no "templates/$t: hooks out of step" "$bad"
	done
}

# -------------------------------------------------------------------- main

# Mandatory, not skipped: a harness that goes quiet without its tools proves
# nothing, and says so least when it matters.
for tool in lefthook commitlint shfmt shellcheck jq; do
	command -v "$tool" >/dev/null 2>&1 || no "harness/$tool not found"
done

make_fixture_repo || exit 1
run_commit_msg
run_commit_msg_output

# Every case_* function must appear here. A defined-but-unregistered case does
# not run, and a test that does not run is the failure this harness exists to
# catch - so the guard below fails the run rather than staying quiet.
cases=(
	case_base_grades_the_message
	case_base_validate_refuses_a_typo
	case_base_rc_refuses_without_mise
	case_base_make_deps_extends
	case_shell_formats_and_restages
	case_shell_shellcheck_refuses
	case_shell_symlink_skipped
	case_shell_check_is_read_only
	case_shell_fix_never_stages
	case_shell_check_without_head
	case_templates_keep_the_split
)

for case_name in "${cases[@]}"; do
	"$case_name"
done

for defined in $(compgen -A function 'case_'); do
	registered=false
	for listed in "${cases[@]}"; do
		[[ $defined == "$listed" ]] && registered=true && break
	done
	$registered || no "harness/$defined is defined but never registered"
done

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
