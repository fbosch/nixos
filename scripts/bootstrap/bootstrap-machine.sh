#!/usr/bin/env bash
set -euo pipefail

repo="fbosch/nixos"
target_dir="$HOME/nixos"
github_device_url="https://github.com/login/device?skip_account_picker=true"

validate_name() {
  local value="$1"
  local label="$2"

  if [ -z "$value" ]; then
    gum style --foreground 1 "$label cannot be empty"
    exit 1
  fi

  if [ "$value" = "." ] || [ "$value" = ".." ]; then
    gum style --foreground 1 "$label cannot be . or .."
    exit 1
  fi

  if [[ $value =~ [^a-zA-Z0-9._-] ]]; then
    gum style --foreground 1 "$label may only contain letters, numbers, ., _, and -"
    exit 1
  fi
}

render_host_module() {
  local preset="$1"
  local host_name="$2"
  local role="$3"
  local system="$4"
  local host_file="$5"

  case "$preset" in
  minimal | desktop | server) ;;
  *)
    gum style --foreground 1 "Unsupported preset: $preset"
    exit 1
    ;;
  esac

  cat >"$host_file" <<EOF_HOST
{ ... }:
{
  hosts."${host_name}" = {
    metadata = {
      role = "${role}";
      system = "${system}";
    };

    modules = [
      "hosts/${host_name}/configuration"
      "hosts/${host_name}/hardware"
      "presets/${preset}"
    ];
  };
}
EOF_HOST
}

render_wrapped_nixos_module() {
  local source_file="$1"
  local module_name="$2"
  local output_file="$3"
  local strip_hardware_import="${4:-false}"

  {
    cat <<EOF_MODULE
{ ... }:
{
  flake.modules.nixos."${module_name}" =
    (
EOF_MODULE

    if [ "$strip_hardware_import" = "true" ]; then
      sed -e 's#\./hardware-configuration\.nix##g' -e 's/^/      /' "$source_file"
    else
      sed -e 's/^/      /' "$source_file"
    fi

    cat <<'EOF_MODULE'
    );
}
EOF_MODULE
  } >"$output_file"
}

validate_generated_module() {
  local module_file="$1"

  if nix-instantiate --parse "$module_file" >/dev/null; then
    return
  fi

  gum style --foreground 1 "Generated module is invalid: $module_file"
  exit 1
}

render_github_device_qr() {
  if ! qrencode \
    --type=ANSIUTF8 \
    --level=M \
    --margin=4 \
    --output=- \
    -- "$github_device_url"; then
    gum style --foreground 3 "QR rendering failed; open the URL above manually."
  fi
}

show_github_device_qr() {
  if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && command -v qrencode >/dev/null 2>&1; then
    render_github_device_qr
  fi
}

authenticate_github_cli() {
  if gh auth status >/dev/null 2>&1; then
    gum style --foreground 2 "GitHub CLI already authenticated."
  else
    gum style --foreground 244 ""
    gum style --foreground 244 "Authenticating GitHub CLI (device flow)."
    gum style --foreground 244 "Use the printed code on another device (phone/laptop)."
    gum style --foreground 244 "Open: $github_device_url"
    show_github_device_qr
    gh auth login --git-protocol ssh --web --skip-ssh-key --scopes admin:public_key
  fi

  if gh auth token >/dev/null 2>&1; then
    if gh api user/keys --jq '.[0].id' >/dev/null 2>&1; then
      :
    else
      gum style --foreground 244 "Refreshing GitHub auth scopes for SSH key management."
      gh auth refresh -h github.com -s admin:public_key
    fi
  fi
}

resolve_host_name() {
  local detected_host_name="$1"
  local requested_host_name="${NIXOS_INSTALL_HOST:-}"

  if [ -n "$requested_host_name" ]; then
    printf '%s\n' "$requested_host_name"
    return
  fi

  if [ -n "$detected_host_name" ]; then
    printf '%s\n' "$detected_host_name"
    return
  fi

  gum input --prompt "Host name: "
}

if [ "${BOOTSTRAP_MACHINE_LIB_ONLY:-false}" = "true" ]; then
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0
  fi
  exit 0
fi

default_host_name=""
if [ -r /etc/hostname ]; then
  default_host_name="$(tr -d '\n' </etc/hostname)"
fi

reuse_existing_repo="false"
if [ -d "$target_dir" ]; then
  if [ -d "$target_dir/.git" ]; then
    reuse_existing_repo="true"
    gum style --foreground 3 "Reusing existing repo at $target_dir"
  else
    gum style --foreground 1 "Error: $target_dir exists but is not a git repository"
    gum style --foreground 244 "Move it away or remove it, then run install again."
    exit 1
  fi
fi

if [ "$reuse_existing_repo" = "false" ] &&
  { [ ! -f /etc/nixos/configuration.nix ] || [ ! -f /etc/nixos/hardware-configuration.nix ]; }; then
  gum style --foreground 1 "Error: expected /etc/nixos/configuration.nix and /etc/nixos/hardware-configuration.nix"
  gum style --foreground 244 "Run this from a freshly installed NixOS machine."
  exit 1
fi

if [ "$reuse_existing_repo" = "true" ] && [ "${BOOTSTRAP_MACHINE_REEXECUTED:-false}" != "true" ]; then
  running_script_hash="$(git hash-object "$0")"

  gum style --foreground 244 "Updating $target_dir before continuing..."
  if ! git -C "$target_dir" pull --ff-only; then
    gum style --foreground 1 "Failed to fast-forward $target_dir"
    gum style --foreground 244 "Resolve the repository state before rerunning bootstrap."
    exit 1
  fi

  repo_script="$target_dir/scripts/bootstrap/bootstrap-machine.sh"
  if [ ! -f "$repo_script" ]; then
    gum style --foreground 1 "Error: expected $repo_script after updating the repository"
    exit 1
  fi

  repo_script_hash="$(git hash-object "$repo_script")"
  if [ "$running_script_hash" != "$repo_script_hash" ]; then
    gum style --foreground 244 "Restarting with the bootstrap script from the updated repository."
    BOOTSTRAP_MACHINE_REEXECUTED=true exec bash "$repo_script"
  fi
fi

gum style --border rounded --padding "1 2" \
  "NixOS bootstrap" \
  "This flow will authenticate GitHub, clone $repo, copy /etc/nixos configs," \
  "and generate host modules."

host_name="$(resolve_host_name "$default_host_name")"
validate_name "$host_name" "Host name"

gum style --foreground 244 "Host name: $host_name"

if gum confirm "Proceed with bootstrap?"; then
  :
else
  gum style --foreground 3 "Aborted."
  exit 0
fi

if [ "$reuse_existing_repo" = "false" ]; then
  authenticate_github_cli

  gum style --foreground 244 ""
  gum style --foreground 244 "Cloning $repo into $target_dir"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ -f "$HOME/.ssh/known_hosts" ] && grep -q '^github.com ' "$HOME/.ssh/known_hosts"; then
    :
  else
    cat >>"$HOME/.ssh/known_hosts" <<'EOF_KNOWN_HOSTS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
EOF_KNOWN_HOSTS
    chmod 600 "$HOME/.ssh/known_hosts"
  fi

  ssh_key_path="$HOME/.ssh/id_ed25519"
  ssh_pub_path="${ssh_key_path}.pub"

  if [ -f "$ssh_key_path" ]; then
    if [ ! -f "$ssh_pub_path" ]; then
      gum style --foreground 244 "Recreating missing public key from $ssh_key_path."
      ssh-keygen -y -f "$ssh_key_path" >"$ssh_pub_path"
      chmod 644 "$ssh_pub_path"
    fi
  elif [ -f "$ssh_pub_path" ]; then
    gum style --foreground 1 "Error: $ssh_pub_path exists without its private key"
    exit 1
  else
    gum style --foreground 244 "No SSH key found at $ssh_key_path; generating one."
    ssh-keygen -t ed25519 -N "" -f "$ssh_key_path"
  fi

  local_pubkey="$(awk 'NF >= 2 { print $1 " " $2; exit }' "$ssh_pub_path")"
  if [ -z "$local_pubkey" ]; then
    gum style --foreground 1 "Error: could not read an SSH public key from $ssh_pub_path"
    exit 1
  fi

  remote_pubkeys="$(gh api user/keys --jq '.[].key')"
  key_added="false"
  if printf '%s\n' "$remote_pubkeys" | awk 'NF >= 2 { print $1 " " $2 }' | grep -Fqx "$local_pubkey"; then
    :
  else
    gum style --foreground 244 "Adding SSH public key to GitHub account."
    gh ssh-key add "$ssh_pub_path" --title "${host_name}-nixos"
    key_added="true"
  fi

  if [ "$key_added" = "true" ]; then
    gum style --foreground 244 "Waiting for GitHub to propagate the new SSH key..."
  fi

  clone_attempts=8
  clone_sleep_seconds=4
  clone_ok="false"

  for attempt in $(seq 1 "$clone_attempts"); do
    if git clone "git@github.com:$repo.git" "$target_dir"; then
      clone_ok="true"
      break
    fi

    if [ "$attempt" -lt "$clone_attempts" ]; then
      gum style --foreground 3 "SSH clone failed (attempt $attempt/$clone_attempts); retrying in ${clone_sleep_seconds}s..."
      sleep "$clone_sleep_seconds"
    fi
  done

  if [ "$clone_ok" = "false" ]; then
    gum style --foreground 1 "SSH clone failed after $clone_attempts attempts."
    gum style --foreground 244 "GitHub key propagation can lag briefly; rerun install in a few seconds."
    exit 1
  fi
fi

hosts_dir="$target_dir/modules/hosts"
if [ ! -d "$hosts_dir" ]; then
  gum style --foreground 1 "Error: expected directory-based hosts at $hosts_dir"
  exit 1
fi

host_rel_dir="modules/hosts/$host_name"
host_rel_file="$host_rel_dir/default.nix"
host_dir="$target_dir/$host_rel_dir"
host_file="$target_dir/$host_rel_file"
use_existing_host="false"
preset=""
role=""
system=""

if [ -f "$host_file" ]; then
  if git -C "$target_dir" ls-files --error-unmatch -- "$host_rel_file" >/dev/null 2>&1; then
    use_existing_host="true"
    gum style --foreground 244 "Host module $host_file exists; using existing host and skipping file generation."
  else
    gum style --foreground 1 "Error: untracked host module exists at $host_file"
    gum style --foreground 244 "Review, stage, or remove the incomplete host directory before rerunning bootstrap."
    exit 1
  fi
elif [ -e "$host_dir" ]; then
  gum style --foreground 1 "Error: incomplete host directory exists at $host_dir"
  gum style --foreground 244 "Review or remove it before rerunning bootstrap."
  exit 1
else
  preset="$(gum choose --header "Select host preset" "minimal" "desktop" "server")"
  role="$(gum choose --header "Select host role" "server" "desktop" "laptop" "vm")"
  system="$(nix-instantiate --eval --expr builtins.currentSystem | tr -d '"')"

  gum style --foreground 244 "Preset: $preset"
  gum style --foreground 244 "Role: $role"
  gum style --foreground 244 "System: $system"
fi

if [ "$use_existing_host" = "false" ]; then
  gum style --foreground 244 ""
  gum style --foreground 244 "Generating host modules in $host_dir"

  generated_dir="$(mktemp -d "$target_dir/.bootstrap-machine.XXXXXX")"
  cleanup_generated_dir() {
    rm -rf "$generated_dir"
  }
  trap cleanup_generated_dir EXIT

  render_host_module "$preset" "$host_name" "$role" "$system" "$generated_dir/default.nix"
  render_wrapped_nixos_module \
    /etc/nixos/configuration.nix \
    "hosts/$host_name/configuration" \
    "$generated_dir/configuration.nix" \
    true
  render_wrapped_nixos_module \
    /etc/nixos/hardware-configuration.nix \
    "hosts/$host_name/hardware" \
    "$generated_dir/hardware.nix"

  validate_generated_module "$generated_dir/default.nix"
  validate_generated_module "$generated_dir/configuration.nix"
  validate_generated_module "$generated_dir/hardware.nix"

  mv "$generated_dir" "$host_dir"
  trap - EXIT

  gum style --foreground 244 "Staging generated host modules in git index..."
  git -C "$target_dir" add -- \
    "$host_rel_dir/default.nix" \
    "$host_rel_dir/configuration.nix" \
    "$host_rel_dir/hardware.nix"
fi

cd "$target_dir"

gpg_status="skipped"
gpg_key_id="fbb.privacy+gpg@protonmail.com"
gpg_key_present="false"

if command -v gpg >/dev/null 2>&1; then
  if gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
    gpg_status="completed"
    gpg_key_present="true"
  fi
fi

if [ "$gpg_key_present" = "false" ]; then
  if nix-shell -p gnupg --run "gpg --list-secret-keys '$gpg_key_id' >/dev/null 2>&1"; then
    gpg_status="completed"
    gpg_key_present="true"
  fi
fi

if [ "$gpg_key_present" = "true" ] && [ -f "./scripts/bootstrap/bootstrap-gpg.sh" ]; then
  gum style --foreground 244 ""
  gpg_reimport_choice="$(gum choose --header "GPG key already exists. Re-import it?" "No" "Yes")"
  if [ "$gpg_reimport_choice" = "Yes" ]; then
    nix-shell -p gh gnupg --run "bash ./scripts/bootstrap/bootstrap-gpg.sh </dev/tty >/dev/tty"
  fi
fi

if [ "$gpg_status" = "skipped" ] && [ -f "./scripts/bootstrap/bootstrap-gpg.sh" ]; then
  if gum confirm "Run GPG bootstrap now?"; then
    nix-shell -p gh gnupg --run "bash ./scripts/bootstrap/bootstrap-gpg.sh </dev/tty >/dev/tty"
    gpg_status="completed"
    gpg_key_present="true"
  fi
fi

gum style --foreground 244 ""
if gum confirm "Run rebuild now?"; then
  sudo env NIX_CONFIG="extra-experimental-features = nix-command flakes" \
    nixos-rebuild switch --accept-flake-config --flake ".#$host_name"
  rebuild_status="completed"
else
  rebuild_status="skipped"
fi

final_rebuild_completed="false"
if [ "$rebuild_status" = "completed" ]; then
  final_rebuild_completed="true"
fi

gum style --foreground 2 ""
gum style --foreground 2 "Bootstrap complete"

if [ "$final_rebuild_completed" = "true" ]; then
  gum style --foreground 244 ""
  if gum confirm "Reboot now?"; then
    sudo reboot
  fi
fi
