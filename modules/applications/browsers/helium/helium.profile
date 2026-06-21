ignore private-cache

include @chromiumProfile@

# Ensure resolver files remain visible in this custom profile
noblacklist /etc/resolv.conf
noblacklist /etc/hosts
noblacklist /etc/nsswitch.conf
noblacklist /run/systemd/resolve/resolv.conf
noblacklist /run/systemd/resolve/stub-resolv.conf
noblacklist /run/NetworkManager/resolv.conf
noblacklist /etc/ssl
noblacklist /etc/pki
noblacklist /etc/static
noblacklist /etc/static/ssl
noblacklist /etc/static/pki

whitelist /etc/resolv.conf
whitelist /etc/hosts
whitelist /etc/nsswitch.conf
whitelist /run/systemd/resolve/resolv.conf
whitelist /run/systemd/resolve/stub-resolv.conf
whitelist /run/NetworkManager/resolv.conf
whitelist /etc/ssl
whitelist /etc/pki
whitelist /etc/static
whitelist /etc/static/ssl
whitelist /etc/static/pki

noblacklist /etc/chromium
noblacklist /etc/chromium/native-messaging-hosts
noblacklist /etc/chromium/native-messaging-hosts/com.8bit.bitwarden.json
noblacklist /etc/static/chromium
noblacklist /etc/static/chromium/native-messaging-hosts
noblacklist /etc/static/chromium/native-messaging-hosts/com.8bit.bitwarden.json
whitelist /etc/chromium
whitelist /etc/chromium/native-messaging-hosts
whitelist /etc/chromium/native-messaging-hosts/com.8bit.bitwarden.json
whitelist /etc/static/chromium
whitelist /etc/static/chromium/native-messaging-hosts
whitelist /etc/static/chromium/native-messaging-hosts/com.8bit.bitwarden.json

# Persist Helium profile data (AppImage uses its own config/cache dirs)
noblacklist ${HOME}/.config/helium-browser
noblacklist ${HOME}/.config/helium
noblacklist ${HOME}/.config/Helium
noblacklist ${HOME}/.config/net.imput.helium
noblacklist ${HOME}/.cache/helium-browser
noblacklist ${HOME}/.cache/helium
noblacklist ${HOME}/.cache/Helium
noblacklist ${HOME}/.cache/net.imput.helium
noblacklist ${HOME}/.cache/com.bitwarden.desktop
noblacklist ${HOME}/.local/state/net.imput.helium

mkdir ${HOME}/.config/helium-browser
mkdir ${HOME}/.cache/helium-browser
mkdir ${HOME}/.config/net.imput.helium
mkdir ${HOME}/.cache/com.bitwarden.desktop
whitelist ${HOME}/.config/helium-browser
whitelist ${HOME}/.config/helium
whitelist ${HOME}/.config/Helium
whitelist ${HOME}/.config/net.imput.helium
whitelist ${HOME}/.cache/helium-browser
whitelist ${HOME}/.cache/helium
whitelist ${HOME}/.cache/Helium
whitelist ${HOME}/.cache/net.imput.helium
whitelist ${HOME}/.cache/com.bitwarden.desktop
whitelist ${HOME}/.local/state/net.imput.helium

# Allow user GTK theme + settings
noblacklist ${HOME}/.themes
noblacklist ${HOME}/.local/share/themes
noblacklist ${HOME}/.nix-profile/share/themes
noblacklist ${HOME}/.nix-profile/share/icons
noblacklist ${HOME}/.local/state/nix/profile/share/themes
noblacklist ${HOME}/.local/state/nix/profile/share/icons
noblacklist /etc/profiles/per-user
noblacklist /run/current-system/sw/share/themes
noblacklist /run/current-system/sw/share/icons

whitelist ${HOME}/.themes
whitelist ${HOME}/.local/share/themes
whitelist ${HOME}/.nix-profile/share/themes
whitelist ${HOME}/.nix-profile/share/icons
whitelist ${HOME}/.local/state/nix/profile/share/themes
whitelist ${HOME}/.local/state/nix/profile/share/icons
whitelist ${HOME}/.config/gtk-3.0
whitelist ${HOME}/.config/gtk-4.0
whitelist ${HOME}/.gtkrc-2.0
whitelist ${HOME}/.config/dconf
whitelist ${HOME}/.config/dconf/user
whitelist /etc/profiles/per-user
whitelist /run/current-system/sw/share/themes
whitelist /run/current-system/sw/share/icons
