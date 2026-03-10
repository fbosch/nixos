#!/usr/bin/env bash

set +e
exit_code=0

gum style --foreground 244 "Linting..."

if gum spin --spinner dot --title "statix" -- statix check --ignore '.agents/**' '.opencode/skills/**' '.github/skills/**' . >/tmp/statix-output 2>&1; then
	echo "$(gum style --foreground 2 '[OK]') statix"
else
	echo "$(gum style --foreground 1 '[FAIL]') statix"
	cat /tmp/statix-output
	echo "  $(gum style --foreground 3 '[HINT]') Run 'statix fix .' to auto-fix issues"
	exit_code=1
fi

if gum spin --spinner dot --title "deadnix" -- deadnix --fail --no-lambda-pattern-names --exclude '.agents' '.opencode/skills' '.github/skills' . >/tmp/deadnix-output 2>&1; then
	echo "$(gum style --foreground 2 '[OK]') deadnix"
else
	echo "$(gum style --foreground 1 '[FAIL]') deadnix"
	cat /tmp/deadnix-output
	exit_code=1
fi

if gum spin --spinner dot --title "format" -- treefmt --no-cache --fail-on-change >/tmp/fmt-output 2>&1; then
	echo "$(gum style --foreground 2 '[OK]') format"
else
	echo "$(gum style --foreground 1 '[FAIL]') format"
	cat /tmp/fmt-output
	echo "  $(gum style --foreground 3 '[HINT]') Run nix run .#fmt to fix"
	exit_code=1
fi

if gum spin --spinner dot --title "actionlint" -- actionlint -shellcheck= >/tmp/actionlint-output 2>&1; then
	echo "$(gum style --foreground 2 '[OK]') actionlint"
else
	echo "$(gum style --foreground 1 '[FAIL]') actionlint"
	cat /tmp/actionlint-output
	exit_code=1
fi

shell_files=$(find scripts configs -type f -name '*.sh' 2>/dev/null || true)
if [ -n "$shell_files" ]; then
	if gum spin --spinner dot --title "shellcheck" -- sh -c "printf '%s\n' \"\$1\" | xargs -r shellcheck -S error" -- "$shell_files" >/tmp/shellcheck-output 2>&1; then
		echo "$(gum style --foreground 2 '[OK]') shellcheck"
	else
		echo "$(gum style --foreground 1 '[FAIL]') shellcheck"
		cat /tmp/shellcheck-output
		exit_code=1
	fi
else
	echo "$(gum style --foreground 244 '[SKIP]') shellcheck (no shell files found)"
fi

if [ "$exit_code" -ne 0 ]; then
	echo "$(gum style --foreground 1 '[ERROR]') Lint failed"
else
	echo "$(gum style --foreground 2 '[DONE]') All checks passed"
fi

exit "$exit_code"
