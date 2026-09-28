#!/usr/bin/env bash
#
# Install a published release's grader the way a consumer does - mise's
# github: backend, from GitHub - and grade one good and one bad message.
# Isolated mise dirs: nothing leaks into, or is borrowed from, this machine's.
#   scripts/smoke.sh v0.1.0
#
# No errexit: each step is checked where it can fail.
set -uo pipefail

die() {
	printf 'smoke: %s\n' "$*" >&2
	exit 1
}

tag=${1-}
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	printf 'usage: %s <vX.Y.Z>\n' "$0" >&2
	exit 2
}

src=$(cd "$(dirname "$0")/.." && pwd) || die 'cannot find the repo'
dir=$(mktemp -d "${TMPDIR:-/tmp}/repokit-smoke.XXXXXX") || die 'mktemp failed'
trap 'rm -rf "$dir"' EXIT
export MISE_DATA_DIR=$dir/data MISE_CACHE_DIR=$dir/cache
export MISE_CONFIG_DIR=$dir/config MISE_STATE_DIR=$dir/state MISE_YES=1

repo=$dir/repo
git init -q "$repo" || die 'git init failed'
cd "$repo" || die "cannot enter $repo"
# The consumer's pin, from templates/base, at this tag's version: the smoke
# proves the line people copy, not one written here.
pin=$(grep '^"github:fabbrito/repokit"' "$src/templates/base/mise.toml") ||
	die 'no repokit pin in templates/base/mise.toml'
pin=$(sed -E 's/version = "[^"]*"/version = "'"${tag#v}"'"/' <<<"$pin")
printf '[tools]\n%s\n' "$pin" >mise.toml
mkdir -p .config
printf 'schema = 2\ntypes = feat\n' >.config/commit-msg.conf

mise install >/dev/null 2>&1 || die "mise cannot install github:fabbrito/repokit@${tag#v}"

got=$(mise exec -- commit-msg-lint version) || die 'commit-msg-lint version failed'
[[ $got == *"$tag"* ]] || die "installed grader says $got, not $tag"

printf 'feat: a\n' | mise exec -- commit-msg-lint - ||
	die 'a good message was refused'
printf 'nope\n' | mise exec -- commit-msg-lint - 2>/dev/null
(($? == 1)) || die 'a bad message was not refused with 1'

printf 'smoke: %s installs through mise and grades\n' "$tag"
