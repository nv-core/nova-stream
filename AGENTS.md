# Agent Instructions for nova-stream

nova-stream is a **Kodi appliance** bootc image derived from the
[finpilot](https://github.com/projectbluefin/finpilot) template. Read
`README.md` first — the "What Makes this Raptor Different?" section is the
authoritative description of what this image changes.

## Git and identity

**Never use the host `git` or `gh` in this repository.** All git operations go
through the containerized wrapper:

```bash
nv-core-git status
nv-core-git add -A
nv-core-git commit -m "feat: ..."
nv-core-git push
```

`nv-core-git` is a symlink to `../scambert-git`. It commits as
`Nova Core Team <nv-core@users.noreply.github.com>`, authenticates with the
podman secret `nv-core-pat`, forces UTC timestamps, and routes all remote
traffic through the VPN SOCKS5 proxy. Using host git leaks the machine owner's
identity, which is the exact thing the wrapper exists to prevent.

Repo-local `user.name`/`user.email` must stay **unset** — identity is forced by
the wrapper via `-c`.

Remote: `https://github.com/nv-core/nova-stream.git`

## Branch strategy (inherited from finpilot)

- `main` is the **testing branch** — publishes `:stable-testing` / `:beta-testing`
- `stable` is the **production branch** — publishes `:stable` / `:beta`
- Promotion is `main` → `stable` via the squash PR from
  `promote-main-to-stable.yml`. Never commit directly to `stable`.

## The two tracks

| Containerfile        | Fedora | Kodi   | Tag       |
| -------------------- | ------ | ------ | --------- |
| `Containerfile`      | 43     | 21.3   | `:stable` |
| `Containerfile.beta` | 44     | 22.0b1 | `:beta`   |

Keep the two Containerfiles in lockstep. Only the `FROM` digest,
`FEDORA_MAJOR_VERSION`, `UBLUE_IMAGE_TAG` and `KODI_TRACK` may differ. A change
to the build steps of one belongs in both.

Both are driven by the same `build/*.sh` scripts — put logic there, not in the
Containerfiles.

## Critical rules

1. **ALWAYS** use Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`)
2. **ALWAYS** use `dnf5` (never `dnf`, `yum`, `rpm-ostree`) with `-y`
3. **ALWAYS** follow the numbered script convention: `10-*.sh`, `20-*.sh`
4. **ALWAYS** run `shellcheck build/*.sh` and validate YAML before committing
5. **ALWAYS** disable COPRs after use (`copr_install_isolated`)
6. **NEVER** commit `cosign.key`
7. **NEVER** push directly to `main` or `stable`
8. **NEVER** reintroduce the `common` or `brew` OCI context stages — see README
9. **ALWAYS** confirm with the user before committing or pushing

## Appliance invariants

Breaking any of these ships a box that boots to a black screen:

- `kodi.service` needs `PAMName=login` **and** a real `TTYPath` — that pairing
  is what gets it a logind seat and therefore DRM master.
- The `kodi` user must stay in `video`, `render`, `input` and `audio`.
- `getty@tty1` must stay disabled; Kodi owns tty1.
- Kodi must be installed from RPM Fusion **free**; the freeworld mesa drivers
  come from **nonfree**. Both repos are required.
- PipeWire/WirePlumber ship with `base-atomic` and Kodi links against
  `libpipewire`, so they cannot be uninstalled. Their **user units are masked**
  in `20-appliance.sh` — do not unmask them, or bitstream passthrough degrades
  to stereo PCM.
- `20-appliance.sh` asserts that `kodi-standalone` and the `kodi-gbm` session
  file exist. Do not weaken those checks — they are what stops a broken image
  from reaching a TV.

## Known quirks (learned the hard way — do not re-derive)

**`base-main` does not exist.** finpilot's template comments name
`quay.io/fedora-ostree-desktops/base-main` as the no-desktop base. The correct
image is `base-atomic`. Do not "fix" our `FROM` lines back to `base-main`.

**`base-atomic` is not minimal.** It ships ~1270 packages including Firefox
(~280 MB), the ibus input-method stack, PipeWire/WirePlumber and
xdg-desktop-portal. `10-build.sh` removes Firefox and ibus; anything else you
strip needs a `dnf5 remove --assumeno` dependency dry-run first.

**mesa freeworld installs differently per Fedora release.** On F43
`mesa-va-drivers` is its own package and the freeworld build must be *swapped*
in. On F44 that package no longer exists (folded into `mesa-dri-drivers`) and
the freeworld build *installs alongside*; swapping there makes dnf try to remove
`mesa-dri-drivers`, which takes `mesa-libGL` with it and fails the build with a
wall of "none of the providers can be installed". `10-build.sh` branches on
`rpm -q mesa-va-drivers` to handle both. Keep that branch when adding tracks.

**Do not install `mesa-vdpau-drivers-freeworld`.** It is obsoleted by
`mesa-va-drivers-freeworld`, so dnf reports "Nothing to do" and the package
never appears — which looks like a broken build when you go looking for it.
VAAPI is the path Kodi uses on Intel and AMD.

## Hardware

Built for Intel and AMD graphics. An NVIDIA variant is planned (via
`ghcr.io/ublue-os/akmods-nvidia-open`) but deliberately not built yet.

**Last Updated**: 2026-08-13
