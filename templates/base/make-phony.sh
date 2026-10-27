#!/usr/bin/env bash
# templates/base: copy to .config/make-phony.sh. Every target `make help`
# lists - `name: ## text` - is a command, never a file, so each must be
# .PHONY: undeclared, a directory of the same name (build/) makes `make build`
# "up to date" and runs nothing. make's own database says what is phony: it
# has read every include.
set -uo pipefail

root=$(git rev-parse --show-toplevel) || exit
cd "$root" || exit

declare -A phony
while IFS= read -r line; do
	[[ $line == '.PHONY: '* ]] || continue
	read -ra targets <<<"${line#.PHONY: }"
	for target in "${targets[@]}"; do
		phony[$target]=1
	done
done < <(make -pRrq -f Makefile : 2>/dev/null)

missing=()
for file in Makefile .config/make/*.mk; do
	[[ -f $file ]] || continue
	while IFS= read -r line; do
		[[ $line =~ ^([a-zA-Z_-]+):.*## ]] || continue
		target=${BASH_REMATCH[1]}
		[[ -v phony[$target] ]] || missing+=("$file: $target")
	done <"$file"
done

if ((${#missing[@]} > 0)); then
	printf 'not .PHONY: %s\n' "${missing[@]}" >&2
	echo 'write: .PHONY: <target>, above the rule' >&2
	exit 1
fi
