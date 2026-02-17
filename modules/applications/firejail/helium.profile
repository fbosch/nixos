include @chromiumProfile@

# Ensure resolver files remain visible in this custom profile
noblacklist /etc/resolv.conf
noblacklist /etc/hosts
noblacklist /etc/nsswitch.conf
noblacklist /run/systemd/resolve/resolv.conf
noblacklist /run/systemd/resolve/stub-resolv.conf
noblacklist /run/NetworkManager/resolv.conf

whitelist /etc/resolv.conf
whitelist /etc/hosts
whitelist /etc/nsswitch.conf
whitelist /run/systemd/resolve/resolv.conf
whitelist /run/systemd/resolve/stub-resolv.conf
whitelist /run/NetworkManager/resolv.conf

# Persist Helium profile data (AppImage uses its own config/cache dirs)
noblacklist ${HOME}/.config/helium-browser
noblacklist ${HOME}/.config/helium
noblacklist ${HOME}/.config/Helium
noblacklist ${HOME}/.config/net.imput.helium
noblacklist ${HOME}/.cache/helium-browser
noblacklist ${HOME}/.cache/helium
noblacklist ${HOME}/.cache/Helium
noblacklist ${HOME}/.cache/net.imput.helium
noblacklist ${HOME}/.local/state/net.imput.helium

mkdir ${HOME}/.config/helium-browser
mkdir ${HOME}/.cache/helium-browser
mkdir ${HOME}/.config/net.imput.helium
whitelist ${HOME}/.config/helium-browser
whitelist ${HOME}/.config/helium
whitelist ${HOME}/.config/Helium
whitelist ${HOME}/.config/net.imput.helium
whitelist ${HOME}/.cache/helium-browser
whitelist ${HOME}/.cache/helium
whitelist ${HOME}/.cache/Helium
whitelist ${HOME}/.cache/net.imput.helium
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
