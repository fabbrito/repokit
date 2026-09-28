#!/usr/bin/env bash
#
# The whole harness. Plain bash and fixtures; bats only if this outgrows
# itself.
#
#   tests/commit-msg/<name>.msg + <name>.expect   expected exit code
#   case_*                                        throwaway repos, built here
#
# lefthook's mechanics are lefthook's to test - stashing, chunking, globbing.
# These cases prove only what is ours: the grader, and the templates - which
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

grader=$PWD/bin/commit-msg-lint.sh
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

# Grading is pure text in, exit code out - but the grader locates its conf
# with `rev-parse --show-toplevel` and skips a message mid-rebase, so it must
# run inside a repo. Its own, never this one: a rebase in progress here would
# otherwise pass every fixture.
fixture_repo=''
repo=''

make_fixture_repo() {
	fixture_repo=$(mktemp -d -p "$tmproot") || return 1
	git -C "$fixture_repo" init -q
	mkdir -p "$fixture_repo/tests"
	cp -r tests/commit-msg "$fixture_repo/tests/commit-msg"
}

# grade <name> [VAR=value ...]
grade() {
	local name=$1
	shift
	(cd "$fixture_repo" &&
		COMMIT_MSG_CONF=$fixture_repo/tests/commit-msg/commit-msg.conf \
			env "$@" "$grader" "tests/commit-msg/$name.msg" 2>&1)
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
		# A rejection may speak; a pass must not. A stray `note` on the success
		# path would otherwise hit every commit with nothing to catch it.
		if ((want == 0)); then
			[[ -z $out ]] || no "commit-msg/$name passes silently" "$out"
		fi
	done
}

# Rejections must say what to write, not just what is wrong.
run_commit_msg_output() {
	local out
	out=$(grade bad-scope)
	want_in 'commit-msg/bad-scope names the scopes' 'alpha' "$out"

	out=$(grade bad-period)
	want_not_in 'commit-msg/bad-period stays quiet about scopes' \
		'scopes:' "$out"

	# Wrapped prose is one rejection, not one per line.
	out=$(grade bad-prose-body)
	want_in 'commit-msg/bad-prose-body names the run' \
		'body is prose, not bullets (lines 3-5)' "$out"
	want_not_in 'commit-msg/bad-prose-body rejects once' \
		'is not a bullet' "$out"

	# A wrapped bullet names the bullet and the wrap, so the fix is not
	# "prefix a dash" - which the next pass would reject as a third bullet.
	out=$(grade bad-wrapped-bullet)
	want_in 'commit-msg/bad-wrapped-bullet names the wrap' \
		'bullet wraps across lines 3-4' "$out"
	want_in 'commit-msg/bad-wrapped-bullet says one bullet per line' \
		'one bullet per line' "$out"
	want_not_in 'commit-msg/bad-wrapped-bullet does not suggest a dash' \
		'write: -' "$out"

	# A rebase replays messages it did not author.
	mkdir -p "$fixture_repo/.git/rebase-merge"
	grade bad-shape >/dev/null 2>&1
	want_exit 'commit-msg/mid-rebase grades nothing' 0 $?
	rmdir "$fixture_repo/.git/rebase-merge"
}

# ------------------------------------------------------------------ grader

# A throwaway repo in $repo, its conf read from stdin into the default path.
# Not a command substitution: a heredoc inside $( ) has its body outside it,
# which bash warns about and then guesses at.
mkrepo() {
	repo=$(mktemp -d -p "$tmproot") || return 1
	git -C "$repo" init -q
	git -C "$repo" config user.email 'test@example.com'
	git -C "$repo" config user.name 'test'
	mkdir -p "$repo/.config"
	cat >"$repo/.config/commit-msg.conf"
}

# Run the grader inside the current fixture repo, stderr folded in.
in_repo() {
	(cd "$repo" && "$grader" "$@" 2>&1)
}

case_grades_stdin() {
	local out
	mkrepo <<-'CONF' || return
		schema = 2
		types  = feat
	CONF
	out=$(printf 'nope\n' | in_repo -)
	want_exit 'grader/grades a message on stdin' 1 $?
	want_in 'grader/stdin rejection says the shape' 'the shape' "$out"

	printf 'feat: a\n' | in_repo - >/dev/null
	want_exit 'grader/a good message on stdin passes' 0 $?
}

# The path is the caller's: relative to where it stands, not to the root the
# grader moves to for the conf.
case_relative_path_from_a_subdir() {
	local out
	mkrepo <<-'CONF' || return
		schema = 2
		types  = feat
	CONF
	mkdir -p "$repo/deep"
	printf 'nope\n' >"$repo/deep/m"
	out=$(cd "$repo/deep" && "$grader" m 2>&1)
	want_exit 'grader/a relative path from a subdir is graded' 1 $?
	want_not_in 'grader/a relative path resolves' 'no such message file' "$out"
}

case_outside_a_repo() {
	local dir out
	dir=$(mktemp -d -p "$tmproot") || return
	printf 'feat: a\n' >"$dir/m"
	out=$(cd "$dir" && "$grader" m 2>&1)
	want_exit 'grader/outside a repo exits 2' 2 $?
	want_in 'grader/outside a repo says so' 'not inside a git repository' "$out"
}

case_no_conf() {
	local out
	mkrepo </dev/null || return
	rm "$repo/.config/commit-msg.conf"
	out=$(printf 'feat: a\n' | in_repo -)
	want_exit 'grader/no conf exits 2' 2 $?
	want_in 'grader/no conf names the path' '.config/commit-msg.conf' "$out"
}

case_cli_surface() {
	local out
	mkrepo <<-'CONF' || return
		schema = 2
	CONF
	out=$(in_repo version)
	want_exit 'cli/version exits 0' 0 $?
	want_in 'cli/version names the schema' 'schema 2' "$out"

	in_repo >/dev/null
	want_exit 'cli/no arguments exits 2' 2 $?

	in_repo a b >/dev/null
	want_exit 'cli/two arguments exits 2' 2 $?

	out=$(in_repo nope.msg)
	want_exit 'cli/a missing file exits 2' 2 $?
	want_in 'cli/a missing file is named' 'no such message file' "$out"
}

# ------------------------------------------------------------------ config

case_conf_unknown_key() {
	local out
	mkrepo <<-'CONF' || return
		schema = 2
		subjet_max = 72
	CONF
	out=$(printf 'feat: a\n' | in_repo -)
	want_exit 'conf/unknown key exits 2' 2 $?
	want_in 'conf/unknown key names the key' 'subjet_max' "$out"
}

case_conf_bad_value() {
	mkrepo <<-'CONF' || return
		schema      = 2
		subject_max = wide
	CONF
	printf 'feat: a\n' | in_repo - >/dev/null
	want_exit 'conf/bad value exits 2' 2 $?
}

case_conf_unknown_schema() {
	local out
	mkrepo <<-'CONF' || return
		schema = 99
	CONF
	out=$(printf 'feat: a\n' | in_repo -)
	want_exit 'conf/unknown schema exits 2' 2 $?
	want_in 'conf/a newer schema says the grader is stale' \
		'grader is stale' "$out"
}

# Schema 1 carried lanes. Absent means 1, so an unmigrated conf lands here
# and must say where the lanes went.
case_conf_schema_one() {
	local out
	mkrepo <<-'CONF' || return
		types = feat
	CONF
	out=$(printf 'feat: a\n' | in_repo -)
	want_exit 'conf/schema 1 exits 2' 2 $?
	want_in 'conf/schema 1 says where lanes went' 'lefthook.yml' "$out"
	want_in 'conf/schema 1 says what to write' 'schema = 2' "$out"
}

case_conf_group_section() {
	local out
	mkrepo <<-'CONF' || return
		schema = 2

		[group shell]
		run = shfmt -d
	CONF
	out=$(printf 'feat: a\n' | in_repo -)
	want_exit 'conf/a [group] section exits 2' 2 $?
	want_in 'conf/a [group] section says where lanes went' \
		'lanes moved to lefthook.yml' "$out"
}

# A second `types` replaced the first and the policy narrowed - the one
# config typo nothing downstream can catch.
case_conf_duplicate_key() {
	local out
	mkrepo <<-'CONF' || return
		schema = 2
		types  = feat
		types  = fix
	CONF
	out=$(printf 'feat: a\n' | in_repo -)
	want_exit 'conf/a duplicate key exits 2' 2 $?
	want_in 'conf/a duplicate key names both lines' 'first at line 2' "$out"
	want_in 'conf/a duplicate key says what to write' \
		'write one types line' "$out"
}

# --------------------------------------------------------------- templates

# A consumer repo in $repo: conf, the named templates copied where the README
# says, a lefthook.yml extending them, hooks installed. base always, and
# first. The rc guard is left out - it needs mise, and gets its own case.
mkconsumer() {
	local t list=''
	mkrepo <<-'CONF' || return 1
		schema      = 2
		types       = feat fix
		scope_fixed = app
	CONF
	mkdir -p "$repo/.config/lefthook"
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

# base calls the grader by name, from PATH, and hands it the message.
case_base_grades_the_message() {
	local out
	mkconsumer || return
	printf 'x\n' >"$repo/a.txt"
	git -C "$repo" add a.txt

	out=$(commit 'nope')
	want_exit 'base/a bad message is refused' 1 $?
	want_in 'base/the refusal is the grader' 'commit-msg-lint: subject' "$out"

	commit 'feat(app): add a' >/dev/null
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
for tool in lefthook shfmt shellcheck jq; do
	command -v "$tool" >/dev/null 2>&1 || no "harness/$tool not found"
done

# Consumers find the grader on PATH, as mise puts it there. The tree's own.
PATH=$src/bin:$PATH

make_fixture_repo || exit 1
run_commit_msg
run_commit_msg_output

# Every case_* function must appear here. A defined-but-unregistered case does
# not run, and a test that does not run is the failure this harness exists to
# catch - so the guard below fails the run rather than staying quiet.
cases=(
	case_grades_stdin
	case_relative_path_from_a_subdir
	case_outside_a_repo
	case_no_conf
	case_cli_surface
	case_conf_unknown_key
	case_conf_bad_value
	case_conf_unknown_schema
	case_conf_schema_one
	case_conf_group_section
	case_conf_duplicate_key
	case_base_grades_the_message
	case_base_validate_refuses_a_typo
	case_base_rc_refuses_without_mise
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
