#!/usr/bin/env bash

set +e
exit_code=0

gum style --foreground 244 "Pre-commit checks..."

staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep -v '^\.agents/' | grep -v '^\.github/skills/' | grep -v '^\.opencode/skills/' || true)

if [ -n "$staged_files" ]; then
	if gum spin --spinner dot --title "format" -- sh -c "printf '%s\n' \"\$1\" | xargs -r treefmt --no-cache" -- "$staged_files"; then
		echo "$(gum style --foreground 2 '[OK]') format (auto-fixed)"
		printf '%s\n' "$staged_files" | xargs -r git add
	else
		echo "$(gum style --foreground 1 '[FAIL]') format"
		exit_code=1
	fi
else
	echo "$(gum style --foreground 244 '[SKIP]') format (no staged files)"
fi

if [ -n "$staged_files" ]; then
	if gum spin --spinner dot --title "statix (fixing)" -- sh -c "printf '%s\n' \"\$1\" | xargs -r -n 1 statix fix" -- "$staged_files" >/tmp/statix-fix-output 2>&1; then
		if [ -s /tmp/statix-fix-output ]; then
			printf '%s\n' "$staged_files" | xargs -r git add
			echo "$(gum style --foreground 3 '[FIXED]') statix auto-fixed issues"
		fi
	else
		echo "$(gum style --foreground 1 '[FAIL]') statix fix failed"
		cat /tmp/statix-fix-output
		exit_code=1
	fi
fi

if [ "$exit_code" -eq 0 ]; then
	if gum spin --spinner dot --title "statix" -- statix check --ignore '.agents/**' '.opencode/skills/**' '.github/skills/**' . >/tmp/statix-output 2>&1; then
		echo "$(gum style --foreground 2 '[OK]') statix"
	else
		echo "$(gum style --foreground 1 '[FAIL]') statix"
		cat /tmp/statix-output
		echo "  $(gum style --foreground 3 '[HINT]') Some issues cannot be auto-fixed - please fix manually"
		exit_code=1
	fi
fi

if gum spin --spinner dot --title "deadnix" -- deadnix --fail --no-lambda-pattern-names --exclude '.agents' '.opencode/skills' '.github/skills' . >/tmp/deadnix-output 2>&1; then
	echo "$(gum style --foreground 2 '[OK]') deadnix"
else
	echo "$(gum style --foreground 1 '[FAIL]') deadnix"
	cat /tmp/deadnix-output
	exit_code=1
fi

staged_workflows=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^\.github/workflows/.*\.(yml|yaml)$' || true)
if [ -n "$staged_workflows" ]; then
	if gum spin --spinner dot --title "actionlint" -- actionlint -shellcheck= >/tmp/actionlint-output 2>&1; then
		echo "$(gum style --foreground 2 '[OK]') actionlint"
	else
		echo "$(gum style --foreground 1 '[FAIL]') actionlint"
		cat /tmp/actionlint-output
		exit_code=1
	fi
else
	echo "$(gum style --foreground 244 '[SKIP]') actionlint (no workflows staged)"
fi

staged_shell=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' || true)
if [ -n "$staged_shell" ]; then
	if gum spin --spinner dot --title "shellcheck" -- sh -c "printf '%s\n' \"\$1\" | xargs -r shellcheck -S error" -- "$staged_shell" >/tmp/shellcheck-output 2>&1; then
		echo "$(gum style --foreground 2 '[OK]') shellcheck"
	else
		echo "$(gum style --foreground 1 '[FAIL]') shellcheck"
		cat /tmp/shellcheck-output
		exit_code=1
	fi
else
	echo "$(gum style --foreground 244 '[SKIP]') shellcheck (no shell scripts staged)"
fi

if [ "$exit_code" -ne 0 ]; then
	echo "$(gum style --foreground 1 '[ERROR]') Pre-commit checks failed"
else
	echo "$(gum style --foreground 2 '[DONE]') All pre-commit checks passed"
fi

exit "$exit_code"
