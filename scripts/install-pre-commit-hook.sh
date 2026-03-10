#!/usr/bin/env bash

set -euo pipefail

if [ ! -f .git/hooks/pre-commit ] || ! grep -q "pre-commit-wrapper" .git/hooks/pre-commit 2>/dev/null; then
	mkdir -p .git/hooks
	cat >.git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exec nix run .#pre-commit-wrapper "$@"
EOF
	chmod +x .git/hooks/pre-commit
	echo "$(gum style --foreground 2 '[OK]') Installed pre-commit hook with nice formatting"
fi
