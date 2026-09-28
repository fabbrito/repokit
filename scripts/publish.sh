#!/usr/bin/env bash
#
# Publish what `make release` tagged: master and the tag to origin, then a
# GitHub release carrying scripts/notes.sh's notes and the grader as a bare
# asset named commit-msg-lint - what mise's github: backend installs. Then
# install that asset the way a consumer would and grade with it: the release
# is proven by the bytes people get, not the ones on this disk.
#   make publish [DRY_RUN=1]
#
# A release is never moved after this. A bad one gets the next patch.
#
# A dry run touches neither origin nor gh, reports every refusal instead of
# the first, and prints the notes it would send.
#
# No errexit: each step is checked where it can fail.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

die() {
	printf 'publish: %s\n' "$*" >&2
	exit 1
}

dry=false
if [[ ${1-} == --dry-run ]]; then
	dry=true
	shift
fi

refusals=0
refuse() {
	$dry || die "$@"
	printf 'publish: would refuse: %s\n' "$*" >&2
	((refusals += 1))
	return 0
}

tag=$(git describe --tags --exact-match HEAD 2>/dev/null) ||
	die 'HEAD carries no tag - make release first'
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$tag is not a release tag"
[[ $(git branch --show-current) == master ]] || refuse 'not on master'
[[ -z $(git status --porcelain) ]] || refuse 'tree not clean'
[[ $(<VERSION) == "$tag" ]] || refuse "VERSION is not stamped $tag"
grep -q "^VERSION='$tag'\$" bin/commit-msg-lint.sh ||
	refuse "the grader is not stamped $tag"
command -v gh >/dev/null 2>&1 || refuse 'gh not found'
command -v mise >/dev/null 2>&1 || refuse 'mise not found'

# A file, not a string: the notes are a document, and `gh --notes-file` takes
# one. Their shape is notes.sh's problem, and it runs standalone.
work=$(mktemp -d "${TMPDIR:-/tmp}/repokit-publish.XXXXXX") || die 'mktemp failed'
trap 'rm -rf "$work"' EXIT
notes=$work/notes.md
scripts/notes.sh "$tag" >"$notes" || die 'notes failed'

if $dry; then
	printf 'publish: would send master and %s to origin, then:\n' "$tag"
	printf '  gh release create %s --title "repokit %s" --notes-file - commit-msg-lint\n' \
		"$tag" "$tag"
	printf -- '--- notes ---\n'
	cat "$notes"
	((refusals > 0)) && exit 1
	exit 0
fi

git push origin master || die 'cannot push master'
git push origin "$tag" || die 'cannot push the tag'
# The asset's name is the binary's: mise names a bare download after it.
mkdir -p "$work/asset" || die 'mkdir failed'
cp bin/commit-msg-lint.sh "$work/asset/commit-msg-lint" || die 'cannot stage the asset'
gh release create "$tag" --title "repokit $tag" --notes-file "$notes" \
	"$work/asset/commit-msg-lint" || die 'gh release failed'

scripts/smoke.sh "$tag" || die "$tag is up, but its asset does not grade - cut the next patch"

printf 'publish: %s is up\n' "$tag"
