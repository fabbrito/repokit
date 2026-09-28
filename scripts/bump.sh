#!/usr/bin/env bash
#
# Move templates/base's grader pin - the line consumers copy - to the latest
# published release, then install that pin in isolated mise dirs and check it
# is the tag asked for. This repo never runs the pin: make and the hooks grade
# with the tree's own bin/. Commits nothing: the diff is yours to commit.
#   make bump [DRY_RUN=1]
#
# No errexit: each step is checked where it can fail.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

die() {
	printf 'bump: %s\n' "$*" >&2
	exit 1
}

dry=false
if [[ ${1-} == --dry-run ]]; then
	dry=true
	shift
fi

pinfile=templates/base/mise.toml
re_pin='^"github:fabbrito/repokit" = \{ version = "([^"]+)"'

slug=$(git remote get-url origin 2>/dev/null) || die 'no origin'
slug=${slug%.git}
slug=${slug#*github.com[:/]}

tag=$(gh api "repos/$slug/releases/latest" --jq .tag_name) ||
	die "cannot read the latest release of $slug"
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "latest release is $tag, not a release tag"
want=${tag#v}

line=$(grep -E "$re_pin" "$pinfile") || die "no repokit pin in $pinfile"
[[ $line =~ $re_pin ]]
have=${BASH_REMATCH[1]}

if [[ $have == "$want" ]]; then
	printf 'bump: already on %s\n' "$tag"
	exit 0
fi

if $dry; then
	printf 'bump: would move %s from %s to %s\n' "$pinfile" "$have" "$want"
	exit 0
fi

# `#` delimits the address: the pin itself holds a `/`.
sed -E -i "\\#$re_pin# s/version = \"[^\"]+\"/version = \"$want\"/" "$pinfile" ||
	die "cannot rewrite $pinfile"
line=$(grep -E "$re_pin" "$pinfile")
[[ $line =~ $re_pin && ${BASH_REMATCH[1]} == "$want" ]] ||
	die "rewrote $pinfile, but it still does not pin $want"

# The rewritten line, installed as a consumer would: the same check publish
# runs, against the pin now in the tree.
scripts/smoke.sh "$tag" || die "$pinfile now pins $tag, but it does not install"

printf 'bump: %s pins %s - review and commit\n' "$pinfile" "$tag"
