#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages
# Names confirmed against Fedora 44, which ghcr.io/ublue-os/base-main tracks.
# qt6-wayland is not a Fedora package; the Wayland Qt platform is qt6-qtwayland.
# gtkgreet requires cage, sway, wayfire, or river. cage hosts the greeter only.
# NetworkManager, PipeWire, and WirePlumber are already on base-main.

dnf5 install -y \
    labwc \
    greetd \
    gtkgreet \
    cage \
    waybar \
    fuzzel \
    foot \
    nautilus \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal-wlr \
    wl-clipboard \
    cliphist \
    grim \
    slurp \
    swaylock \
    swayidle \
    wlr-randr \
    wlopm \
    bluez \
    brightnessctl \
    power-profiles-daemon \
    flatpak \
    qt6-qtwayland \
    plymouth \
    plymouth-plugin-script \
    curl \
    rsms-inter-fonts \
    jetbrains-mono-fonts \
    adwaita-cursor-theme

install -d /etc/xdg/labwc /etc/skel/.config/labwc
cp -a /ctx/config/labwc/. /etc/xdg/labwc/
cp -a /ctx/config/labwc/. /etc/skel/.config/labwc/
chmod 755 /etc/xdg/labwc/autostart /etc/skel/.config/labwc/autostart \
    /usr/libexec/elavo-grim-region /usr/libexec/elavo-app-menu

/usr/libexec/gtkgreet-update-environments -w /etc/greetd/environments

# Pinned splash from elavo-visuals. The frames are not stored in this repo.
ELAVO_VISUALS_SHA=7e91404a9b4c84dd2c10cc6819cd6916a07a738e
visuals_tmp=$(mktemp -d)
curl -fsSL -o "${visuals_tmp}/visuals.tar.gz" \
    "https://github.com/elavo-io/elavo-visuals/archive/${ELAVO_VISUALS_SHA}.tar.gz"
tar -xzf "${visuals_tmp}/visuals.tar.gz" -C "${visuals_tmp}"
install -d /usr/share/plymouth/themes/elavo
cp -a "${visuals_tmp}/elavo-visuals-${ELAVO_VISUALS_SHA}/bootscreen/elavo/." /usr/share/plymouth/themes/elavo/
rm -rf "${visuals_tmp}"
test -f /usr/share/plymouth/themes/elavo/elavo.plymouth
test -f /usr/share/plymouth/themes/elavo/elavo.script

plymouth-set-default-theme -R elavo

install -d /etc/dconf/profile /etc/dconf/db/local.d
if [[ ! -f /etc/dconf/profile/user ]]; then
    printf '%s\n' 'user-db:user' 'system-db:local' > /etc/dconf/profile/user
elif ! grep -q '^system-db:local$' /etc/dconf/profile/user; then
    printf '%s\n' 'system-db:local' >> /etc/dconf/profile/user
fi
dconf update

# Flathub is shipped in /etc/flatpak/remotes.d. Firefox is a preinstall file
# under /usr/share/flatpak/preinstall.d. elavo-flatpak-preinstall.service
# applies it after the network is up, because a system Flatpak install lives
# in /var and bootc does not ship /var.

systemctl enable greetd.service elavo-flatpak-preinstall.service
systemctl set-default graphical.target
