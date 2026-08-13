# nova-stream

A **Kodi media appliance** built as a [bootc](https://bootc-dev.github.io/bootc/)
image on Fedora Atomic, maintained by the Nova Core Team.

It behaves like [LibreELEC](https://libreelec.tv/): the box powers on, shows a
splash, and lands in Kodi. There is no desktop, no login screen and no window
manager — Kodi draws straight onto DRM/KMS through its **GBM** backend, which is
the only Kodi windowing backend on Linux that can output **HDR**.

Unlike LibreELEC it is a full Fedora underneath, so the image updates
transactionally, rolls back with one command, and is built from an ordinary
container build.

- **Immutable and transactional** — `bootc` image updates, `bootc rollback` if a
  release misbehaves
- **Hands-off updates** — the box fetches new images and stages them for the
  next boot on its own
- **HDR-capable** — Kodi's GBM/DRM path with `HDR_OUTPUT_METADATA`, driven by
  the TV's EDID
- **Bitstream audio** — ALSA-direct, so DTS-HD MA / TrueHD / Atmos reach the
  receiver untouched
- **CEC remote** — drive Kodi with the TV remote over HDMI, no extra hardware

## Tracks

Two tracks are published, each pinned to the Fedora release that carries its
Kodi version:

| Tag       | Fedora | Kodi      | Use it when                                    |
| --------- | ------ | --------- | ---------------------------------------------- |
| `:stable` | 43     | 21.3      | You want the boring one that works             |
| `:beta`   | 44     | 22.0b1    | You want Kodi 22's HDR and AV1 work            |

`:stable-testing` and `:beta-testing` are published from `main` before
promotion.

```bash
# stable track
sudo bootc switch ghcr.io/nv-core/nova-stream:stable

# Kodi 22 pre-release track
sudo bootc switch ghcr.io/nv-core/nova-stream:beta
```

## What Makes this Raptor Different?

Here are the changes from **Fedora Atomic (`base-atomic`)**. This image is based
on the desktop-less Fedora Atomic base rather than Bluefin or Silverblue,
because the entire point is to not ship a desktop.

### Added Packages (Build-time)

- **Kodi**: `kodi`, `kodi-inputstream-adaptive`, `kodi-inputstream-rtmp`,
  `kodi-peripheral-joystick` — the media centre and the input/streaming addons
  almost every setup ends up needing. `kodi` already depends on `libcec`, so
  HDMI-CEC remote control needs no extra package.
- **Video acceleration**: `mesa-va-drivers-freeworld` (swapped in over Fedora's
  codec-stripped `mesa-va-drivers`), `intel-media-driver`, `libva-intel-driver`,
  `libva-utils`, `mesa-dri-drivers`, `vulkan-loader` — without the freeworld
  swap, H.264/HEVC decoding silently falls back to the CPU. VAAPI is the path
  Kodi uses here; `mesa-va-drivers-freeworld` obsoletes the VDPAU freeworld
  package, so there is deliberately no VDPAU driver installed.
- **Audio**: `alsa-utils`, `alsa-firmware`. PipeWire/WirePlumber ship with the
  base and cannot be removed (Kodi links against `libpipewire`), so their user
  units are masked instead — see below.
- **Network/shares**: `nss-mdns`, `cifs-utils`, `nfs-utils` — SMB/NFS libraries
  and `.local` resolution for mDNS-advertised shares.
- **Boot/diagnostics**: `plymouth`, `plymouth-system-theme`, `tmux`.
- **RPM Fusion**: both `free` (Kodi lives there) and `nonfree` (the freeworld
  mesa drivers live there) are enabled.

### Removed/Disabled

- **No desktop environment** — the base image ships none and none is added.
- **No `@projectbluefin/common` layer** — it is GNOME/Aurora desktop
  configuration; pulling it in would drag desktop config into an image whose
  purpose is not having one.
- **No `@ublue-os/brew` layer** — Homebrew has no role on an appliance.
- **No `custom/` tree** — the upstream template's Brewfile/Flatpak/ujust
  customisation depends on the `common` layer that this image drops.
- **Firefox and ibus removed** — `base-atomic` is less minimal than its name
  suggests and ships both. A 280 MB browser and a full input-method stack have
  no role on a set-top box.
- **`getty@tty1` disabled** — Kodi owns tty1. tty2–tty6 still give you a rescue
  login.
- **No display manager** — the default target is `multi-user.target`.

### Configuration Changes

- **`kodi.service`** runs `kodi-standalone --windowing=gbm` as the `kodi` user
  on tty1, with `PAMName=login` so logind grants it a seat on `seat0`. Without
  that seat there is no DRM master and Kodi exits with "failed to open any DRM
  device".
- **`kodi` user** is declared via `sysusers.d`, not `useradd` — `/var` is not
  part of a bootc image, so systemd creates the account and its home on first
  boot. `tmpfiles.d` creates `/var/lib/kodi`.
- **Kernel arguments** (`bootc/kargs.d`): `quiet splash loglevel=3` and a hidden
  console cursor, so the TV never shows a wall of systemd output.
- **`bootc-fetch-apply-updates.timer` enabled** for hands-off updates.
- **ALSA-direct audio.** The PipeWire/WirePlumber **user units are masked**, so
  nothing claims the HDMI device before Kodi does and bitstreaming reaches the
  receiver intact. If WirePlumber gets the device first, passthrough quietly
  degrades to stereo PCM. This is how LibreELEC does it too.

_Last updated: 2026-08-13_

## Hardware support

Currently built for **Intel and AMD** graphics only. An NVIDIA variant is
planned but not yet built; be aware that GBM plus the proprietary NVIDIA driver
is the weakest path for this workload and HDR parity is not expected there.

HDR needs a GPU whose DRM driver exposes the `HDR_OUTPUT_METADATA` and
`Colorimetry` connector properties. `amdgpu` has the most complete support;
recent Intel is good.

## Building locally

```bash
just build                                       # stable track
just build nova-stream beta Containerfile.beta   # beta track

just build-qcow2                                 # VM image
just build-iso                                   # installable ISO
just run-vm-qcow2                                # boot it
```

A VM will not exercise HDR or CEC — those need real hardware and a real
display.

## Caveats worth knowing

- **Kodi 22 is a pre-release.** The `:beta` track ships `22.0-0.4b1` because
  that is what RPM Fusion has for Fedora 44.
- **The `:stable` track sits on Fedora 43**, which reaches end of life before
  Fedora 44. Both tracks will need to move up a release in time.
- **This is not CoreELEC.** CoreELEC's value is Amlogic ARM SoC support with
  vendor kernels; that is not reachable from Fedora bootc on amd64. What this
  gives you is the LibreELEC *experience* on a Fedora foundation.

## Credits

Built from the [finpilot](https://github.com/projectbluefin/finpilot) bootc
image template by [Universal Blue](https://universal-blue.org/).
