###############################################################################
# nova-stream — stable track (Kodi 21.3 on Fedora 43)
###############################################################################
# A LibreELEC-style Kodi appliance built as a bootc image, maintained by the
# Nova Core Team. No desktop environment: Kodi runs directly on DRM/KMS through
# its GBM windowing backend, which is the only Kodi backend that supports HDR
# output on Linux.
#
# Two tracks are built from this repository:
#   Containerfile       -> stable track: Fedora 43 + Kodi 21.3   (:stable)
#   Containerfile.beta  -> beta   track: Fedora 44 + Kodi 22.0b1 (:beta)
#
# Each track pins its own base digest so Renovate can bump them independently.
#
# DEVIATION FROM UPSTREAM finpilot (deliberate, see README):
#   The @projectbluefin/common and @ublue-os/brew context stages are NOT used.
#   `common` ships GNOME/Aurora desktop configuration and `brew` ships Homebrew;
#   both are meaningless on a set-top appliance and `common` would pull desktop
#   configuration back into an image whose entire purpose is not having one.
###############################################################################

# Context stage - local build scripts and static system files only.
FROM scratch AS ctx

COPY build /build
COPY system_files /system_files

# Base Image - Fedora Atomic with no desktop environment.
# NOTE: finpilot's template comments name `base-main`, which does not exist on
# quay.io. The correct no-desktop Fedora Atomic base is `base-atomic`.
FROM quay.io/fedora-ostree-desktops/base-atomic:43@sha256:b778d9e49d191a702d2eaf858852818737204e8a622e662726f87b2ef1f34752

# Image identity - consumed by build/00-image-info.sh
ARG IMAGE_NAME="nova-stream"
ARG IMAGE_VENDOR="nv-core"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="base-atomic"
ARG FEDORA_MAJOR_VERSION="43"
ARG VERSION=""

# Kodi track selection - consumed by build/10-build.sh
ARG KODI_TRACK="stable"

### MODIFICATIONS

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh

# Kodi, media stack and hardware video acceleration
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh

# Appliance behaviour - kodi user, GBM session, silent boot, auto-updates
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/20-appliance.sh

### CLEANUP
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/clean-stage.sh

### /opt
RUN rm -rf /opt && ln -s /var/opt /opt

### INIT
CMD ["/sbin/init"]

### LINTING
RUN bootc container lint --fatal-warnings
