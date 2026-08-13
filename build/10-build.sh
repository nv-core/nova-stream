#!/usr/bin/bash

set -euo pipefail

###############################################################################
# nova-stream — Kodi and media stack
###############################################################################
# Installs Kodi plus the hardware video acceleration stack. Everything that
# shapes appliance *behaviour* (users, session, boot, updates) lives in
# 20-appliance.sh; this script only puts software on disk.
###############################################################################

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

shopt -s nullglob

FEDORA_MAJOR_VERSION="$(rpm -E %fedora)"

echo "::group:: Configure dnf"

# Write the build-time dnf options directly rather than going through
# `dnf5 config-manager setopt`, which is what the finpilot template does.
#
# That setopt call left a dnf.conf that dnf5 itself then refused to parse
# ("Error in configuration file /etc/dnf/dnf.conf: Missing '=' on line 4") on
# the Fedora 43 CI runner while working on Fedora 44 and in local builds. The
# damage only surfaces on the *next* dnf invocation, which is a separate build
# step, so the error points nowhere near its cause.
#
# Writing the file is deterministic across dnf5 versions, and the parse check
# below fails here - with the file contents - instead of somewhere downstream.
# The base image ships only a comment and an empty [main], so nothing is lost.
cat >/etc/dnf/dnf.conf <<'EOF'
# see `man dnf.conf` for defaults and possible options
[main]
install_weak_deps=0
keepcache=1
EOF

if ! dnf5 -q repoquery --installed bash >/dev/null 2>&1; then
    echo "ERROR: dnf5 cannot parse /etc/dnf/dnf.conf after writing it:" >&2
    cat -n /etc/dnf/dnf.conf >&2
    exit 1
fi

echo "::endgroup::"

echo "::group:: Enable RPM Fusion"

# Kodi lives in RPM Fusion free. The nonfree repo is needed for
# mesa-va-drivers-freeworld, which restores the H.264/HEVC VAAPI decoders that
# Fedora strips out of its own mesa build — without it, hardware decoding on
# AMD and older Intel silently falls back to CPU.
dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_MAJOR_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_MAJOR_VERSION}.noarch.rpm"

echo "::endgroup::"

echo "::group:: Install Kodi"

# The unified `kodi` package carries every windowing backend in one binary
# (GBM, Wayland, X11) and ships /usr/share/wayland-sessions/kodi-gbm.desktop.
# The separate `kodi-gbm` package that older guides mention no longer exists.
# `kodi` already depends on libcec, so HDMI-CEC remote control needs no extra
# package.
dnf5 install -y \
    kodi \
    kodi-inputstream-adaptive \
    kodi-inputstream-rtmp \
    kodi-peripheral-joystick

echo "::endgroup::"

echo "::group:: Install video acceleration"

# Fedora ships mesa with the patented codecs compiled out; RPM Fusion's
# freeworld build restores them. How it has to be installed changed between
# Fedora releases:
#
#   F43 and earlier - mesa-va-drivers is its own package, and the freeworld
#                     build replaces it, so it must be swapped.
#   F44 and later   - mesa-va-drivers no longer exists (it was folded into
#                     mesa-dri-drivers) and the freeworld build installs
#                     alongside it. Swapping here makes dnf try to remove
#                     mesa-dri-drivers, which drags mesa-libGL down with it and
#                     fails the build.
#
# Deciding on what is actually installed keeps both tracks building from one
# script, and keeps working when the stable track moves to a newer Fedora.
if rpm -q mesa-va-drivers >/dev/null 2>&1; then
    echo "mesa-va-drivers present - swapping in the freeworld build"
    dnf5 swap -y mesa-va-drivers mesa-va-drivers-freeworld
else
    echo "mesa-va-drivers absent (merged into mesa-dri-drivers) - installing freeworld alongside"
    dnf5 install -y mesa-va-drivers-freeworld
fi

# NOTE: mesa-va-drivers-freeworld obsoletes mesa-vdpau-drivers-freeworld, so do
# not try to install that too - dnf reports "Nothing to do" and the package
# never appears, which reads like a broken build. VAAPI is the path Kodi uses
# on Intel and AMD; VDPAU is legacy.

dnf5 install -y \
    mesa-dri-drivers \
    intel-media-driver \
    libva-intel-driver \
    libva-utils \
    vulkan-loader

echo "::endgroup::"

echo "::group:: Install audio and network stack"

# Audio is ALSA-direct: Kodi opens the HDMI/SPDIF device exclusively and
# bitstreams DTS-HD MA / Dolby TrueHD / Atmos straight to the receiver. A sound
# server in the path is the usual reason passthrough silently degrades to
# stereo PCM, and an appliance has no second audio client that would justify
# one. This mirrors how LibreELEC does it.
#
# NOTE: base-atomic ships PipeWire and WirePlumber as part of the base, and
# Kodi links against libpipewire, so the packages cannot simply be removed.
# 20-appliance.sh masks their *user* units instead, which keeps the daemons
# from ever claiming the audio device.
dnf5 install -y \
    alsa-utils \
    alsa-firmware

# NetworkManager is present in base-atomic; nss-mdns adds .local name
# resolution so SMB/NFS shares advertised over mDNS resolve.
dnf5 install -y \
    nss-mdns \
    cifs-utils \
    nfs-utils

echo "::endgroup::"

echo "::group:: Install boot and diagnostics"

dnf5 install -y \
    plymouth \
    plymouth-system-theme \
    tmux

echo "::endgroup::"

echo "::group:: Strip desktop leftovers"

# base-atomic is less minimal than its name suggests: it ships Firefox (~280 MB)
# and the full ibus input-method stack, neither of which has any role on a
# set-top box with no desktop. Removing them takes only their own langpacks and
# engines with them - verified with a dependency dry-run.
dnf5 remove -y firefox ibus

echo "::endgroup::"

shopt -u nullglob

echo "Kodi and media stack installed."
