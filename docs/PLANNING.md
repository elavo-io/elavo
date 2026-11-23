# Elavo planning: Fedora 45, effects, Nvidia, pruning, bootloader

Research and decisions as of November 17, 2026.

## Recommended order

1. Fedora 45 migration
2. Native scenefx (SwayFX) effects in labwc
3. Nvidia overlay images
4. Bootloader: GRUB to rEFInd

Image pruning is small and independent; add it alongside whichever step is in progress.

---

## 1. Fedora 45 migration

**Universal Blue status (read from the image labels on ghcr.io, Nov 17, 2026):**

| Image | Tag | Fedora |
| --- | --- | --- |
| bazzite | stable, testing | 45 |
| aurora | stable, latest | 45 |
| bluefin | latest | 45 |
| bluefin | stable | 44 |
| base-main | latest, 45 | 45 |
| silverblue-main | latest, 45 | 45 |

Fedora 45 is the production default for Bazzite and Aurora. Only Bluefin's
conservative stable channel is still on 44.

**Elavo today:** `Containerfile` sets `ARG FEDORA_VERSION=44`, which drives
`ghcr.io/ublue-os/base-main:${FEDORA_VERSION}` and every Fedora build stage
(folio, keyboard, system-settings, app-bay, applications, files, labwc).

**Change:** one line, `FEDORA_VERSION=45`. Then do a test build and check
that every stage still compiles against Fedora 45's packages, and that the
package removals and checks in `build_files/build.sh` still apply.

## 2. Native scenefx (SwayFX) effects

Move the dock's transparency and the other transparency and blur effects
off the current workarounds and onto scenefx, the effects library that
SwayFX uses. labwc already carries scenefx 0.5 as an extra patch in
elavo-labwc-mods; it is not a full fork, because upstream labwc rejected scenefx.

- Dock transparency and blur through scenefx instead of the current hack.
- Other translucent surfaces (panel, menus, popovers) through the same path.
- Remove the old corner clip, shadow and blur workarounds once each one is covered.

## 3. Nvidia overlay images

The base image stays clean and has no Nvidia logic. Nvidia support is
two separate overlay scripts that produce separate images:

| Image | GPUs | Driver |
| --- | --- | --- |
| `elavo-nvidia-open` | Turing (2018) and newer: GTX 16 series, all RTX | NVIDIA open kernel modules |
| `elavo-nvidia-legacy` | Maxwell, Pascal, Volta: GTX 900/1000, Titan V, GTX 750 Ti, GTX 745 | Proprietary driver, 580 LTS branch |
| none | Kepler and older | nouveau only (or unsupported) |

This mirrors Bazzite's split: `bazzite-nvidia-open` for Turing and newer,
and `bazzite-nvidia` for Maxwell, Pascal and Volta. Bazzite documents it in
the FAQ on docs.bazzite.gg (bazzite-org/docs.bazzite.gg, `src/General/FAQ.md`).
Aurora and Bluefin have dropped their legacy Nvidia images; Bazzite keeps one.

Note: the Dell-Elavo-Dev's GeForce MX250 is Pascal, so it falls in the legacy group.

**Status (Nov 18, 2026): written and built locally, not committed or published.**

- Everything is in `nvidia/`: one `Containerfile` layered on the Elavo image,
  `build-nvidia-open.sh` and `build-nvidia-legacy.sh` (one per image), the shared
  `install-nvidia.sh`, and `system_files/` (bootc kernel arguments, labwc environment).
- `just build-nvidia open|legacy [base image]` builds one. `build.yml` builds both after
  the base image and pushes them as `elavo-nvidia-open` and `elavo-nvidia-legacy`.
- Kernel modules are not built here. They are Universal Blue's prebuilt, signed ones:
  `ghcr.io/ublue-os/akmods-nvidia-open` and `akmods-nvidia-lts`, tag
  `main-45-<kernel>`, picked for the base image's kernel.
- First local builds on kernel 7.3.4-300.fc45: open 620.70.06, legacy 580.196.07.
- Still open: boot on real NVIDIA hardware; Secure Boot key enrollment; System Settings'
  driver wizard still names a single `elavo-nvidia` image; ISOs in `build-disk.yml`.

## 4. Image pruning

GitHub never deletes old package versions automatically, and the current
workflows (`build.yml`, `build-disk.yml`) have no cleanup step, so untagged
image versions pile up on ghcr.io.

- Add a scheduled or post-build workflow step that deletes untagged versions
  older than a set age, keeping every tagged release.
- Cost today: none. Packages are free for public packages, and Container
  registry storage and bandwidth are currently free (GitHub promises a month's
  notice before that changes). Pruning is for tidiness and future-proofing.
- The elavo-io org is a separate GitHub account from the personal Pro plan;
  Pro limits do not apply to it.
- Disk images and ISOs uploaded as Actions artifacts expire with the repo's
  default retention (90 days unless changed); they are free for public repos.

## 5. Bootloader: GRUB to rEFInd

**Decision:** replace GRUB with rEFInd. Limine is the alternative.

- EFI only.
- Apple-like graphical theme.
- Auto-hides at boot unless several operating systems are detected or a key is held.

**Zero-friction install:** build rEFInd's install, config, theme and recovery
entry into the first-boot script, so users never have to touch it.

- rEFInd finds other EFI systems on its own. The first-boot script also runs
  a scan so entries are filled in ahead of time.
- Editing the config by hand is only for unusual setups.

**Recovery:** ship the recovery image as a separate tag. Users boot it by
holding a key at the bootloader screen.

**Dual boot:**
- Windows on UEFI and other EFI operating systems work.
- A 2013 Mac dual-booting macOS and Elavo works; rEFInd handles Apple's EFI quirks.
- The only unsupported case is Windows installed in legacy BIOS mode (typically
  pre-2012 installs).
