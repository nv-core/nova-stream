#!/usr/bin/bash

set -euo pipefail

###############################################################################
# nova-stream — appliance behaviour
###############################################################################
# Turns a plain Fedora Atomic image into a set-top appliance: a dedicated kodi
# user, a Kodi-on-GBM session owning tty1, silent boot, and hands-off updates.
###############################################################################

shopt -s nullglob

echo "::group:: Overlay static system files"

rsync -rvK /ctx/system_files/ /

echo "::endgroup::"

echo "::group:: Configure the kodi session"

# The kodi user is declared through sysusers.d rather than useradd because /var
# is not part of a bootc image — systemd creates the account and its home on
# first boot instead.
systemd-sysusers /usr/lib/sysusers.d/kodi.conf

# Kodi owns tty1. Disabling the getty there keeps a login prompt from fighting
# the session for the console; tty2-tty6 remain available for rescue logins.
systemctl disable getty@tty1.service 2>/dev/null || true
systemctl enable kodi.service

# An appliance never needs a graphical login stack.
systemctl set-default multi-user.target

echo "::endgroup::"

echo "::group:: Keep sound servers off the audio device"

# PipeWire and WirePlumber come with base-atomic and Kodi links against
# libpipewire, so the packages have to stay. Masking their user units is what
# actually matters: if wireplumber claims the HDMI device first, Kodi's
# bitstream passthrough quietly degrades to stereo PCM and the receiver stops
# reporting DTS-HD/TrueHD. Masking leaves ALSA as the only path.
systemctl --global mask pipewire.socket pipewire.service \
    pipewire-pulse.socket pipewire-pulse.service \
    wireplumber.service 2>/dev/null || true

echo "::endgroup::"

echo "::group:: Configure updates and services"

# LibreELEC-style hands-off updating: the box pulls new images and stages them
# for the next boot without anyone asking it to.
systemctl enable bootc-fetch-apply-updates.timer

# Time sync matters more than usual here — DRM/HDCP and streaming add-ons both
# misbehave against a skewed clock.
systemctl enable systemd-timesyncd.service 2>/dev/null || true

echo "::endgroup::"

echo "::group:: Verify the GBM session is present"

# Fail the build rather than ship an image that boots to a black screen.
if [[ ! -x /usr/bin/kodi-standalone ]]; then
    echo "ERROR: /usr/bin/kodi-standalone missing — Kodi did not install correctly" >&2
    exit 1
fi

if [[ ! -f /usr/share/wayland-sessions/kodi-gbm.desktop ]]; then
    echo "ERROR: kodi-gbm session file missing — this Kodi build lacks GBM support" >&2
    exit 1
fi

echo "::endgroup::"

shopt -u nullglob

echo "Appliance configuration complete."
