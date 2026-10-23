# shellcheck shell=sh
# templates/base: copy to .config/lefthook-rc.sh. Sourced by every git hook
# before lefthook runs: mise's pinned tools first on PATH. Hooks never see
# `mise activate`, so without this a hook runs whatever apt installed and
# passes on the wrong version - no mise is a failed hook, not a fallback.
if ! command -v mise >/dev/null 2>&1; then
	echo 'lefthook-rc: mise not on PATH - https://mise.jdx.dev, then make deps' >&2
	exit 1
fi
# PATH alone, like make.mk: no eval of generated shell. A repo whose hooks
# need mise's [env] too sets it in its own lane.
mise_path=$(mise bin-paths | paste -sd: -) || exit 1
PATH="$mise_path:$PATH"
export PATH
