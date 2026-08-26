#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

expected_hooks_path=.githooks
config_path=.pre-commit-config.yaml
worktree_config_enabled=$(git config --local --type=bool --get extensions.worktreeConfig || true)

for hook in pre-commit pre-push run; do
  if [[ ! -x "$expected_hooks_path/$hook" ]]; then
    printf 'install-hooks: %s must exist and be executable\n' "$expected_hooks_path/$hook" >&2
    exit 1
  fi
done

if [[ $worktree_config_enabled != true ]]; then
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
  common_bare=$(git config --local --type=bool --get core.bare || true)

  if git config --local --get-all core.worktree >/dev/null || [[ $common_bare == true ]]; then
    printf 'install-hooks: migrate shared core.worktree or core.bare=true before enabling worktree config\n' >&2
    exit 1
  fi

  shopt -s nullglob
  dormant_configs=("$common_dir/config.worktree" "$common_dir"/worktrees/*/config.worktree)
  for dormant_config in "${dormant_configs[@]}"; do
    if [[ -e $dormant_config || -L $dormant_config ]]; then
      printf 'install-hooks: refusing to activate dormant worktree config %s\n' "$dormant_config" >&2
      exit 1
    fi
  done

  git config --local extensions.worktreeConfig true
fi

current_hooks_path=$(git config --worktree --get-all core.hooksPath || true)
if [[ -n $current_hooks_path && $current_hooks_path != "$expected_hooks_path" ]]; then
  printf 'install-hooks: refusing to replace worktree core.hooksPath=%s\n' "$current_hooks_path" >&2
  exit 1
fi

git config --worktree --replace-all core.hooksPath "$expected_hooks_path"
effective_hooks_path=$(git config --get core.hooksPath)
if [[ $effective_hooks_path != "$expected_hooks_path" ]]; then
  printf 'install-hooks: effective core.hooksPath is %s, expected %s\n' "$effective_hooks_path" "$expected_hooks_path" >&2
  exit 1
fi

if [[ -L $config_path ]]; then
  config_target=$(readlink "$config_path")
  case "$config_target" in
  /nix/store/*-pre-commit-config.*)
    unlink "$config_path"
    printf 'Removed generated %s symlink\n' "$config_path"
    ;;
  *) printf 'install-hooks: leaving unexpected %s symlink to %s\n' "$config_path" "$config_target" >&2 ;;
  esac
elif [[ -e $config_path ]]; then
  printf 'install-hooks: leaving existing regular %s unchanged\n' "$config_path" >&2
fi

printf 'Git hooks installed from %s for %s\n' "$expected_hooks_path" "$repo_root"
