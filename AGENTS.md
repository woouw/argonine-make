# AGENTS.md

Context for AI agents working on this repo.

## What this is

Minimal Alpine Linux image for the Anbernic RG35XX H handheld (Allwinner H700, quad Cortex-A53, aarch64). Boots to a TTY with Wi-Fi ready. No desktop by default. The hardware layer (kernel, U-Boot, DTBs, firmware) is reused from a ROCKNIX release — nothing is compiled from source.

## Hardware

- **SoC:** Allwinner H700 (aarch64, quad Cortex-A53)
- **GPU:** Mali G31 (Panfrost in mainline)
- **Display:** DSI panel, two variants — regular and rev6 (baked into build via `PANEL=`)
- **Kernel:** 7.2.0 from ROCKNIX 20261001
- **Boot:** U-Boot SPL at 8K offset → extlinux.conf → kernel + rootfix.cpio + DTB → Alpine OpenRC
- **rootfix.cpio trick:** ROCKNIX's built-in initramfs lacks a `/root` directory. rootfix.cpio adds it so the kernel can pivot. `rdinit=/nonexistent` bypasses ROCKNIX's LibreELEC init entirely.

## Repo layout

```
build/
  config.sh           central config, sourced by every script; loads local.env if present
  lib/util.sh         shared helpers: die(), fetch(), in_chroot(), in_chroot_exec()
  build-all.sh        runs all steps in order
  01-fetch-rocknix.sh download + verify ROCKNIX image
  02-extract-rocknix.sh  gunzip, extract kernel/DTBs/bootloader/modules/firmware via mtools + unsquashfs
  03-rootfs.sh        extract Alpine minirootfs, apk install, users, fstab, modules, overlay
  04-services.sh      wire up OpenRC runlevel symlinks
  05-image.sh         assemble flashable .img (no loop devices: mtools for FAT, mkfs.ext4 -d for root)
overlay/
  etc/doas.conf               permit :wheel
  etc/init.d/rg35xxh-resize   first-boot partition resize, self-destructs after success
  etc/init.d/rg35xxh-sysfs    early sysfs mount
  etc/udev/rules.d/70-rg35xxh-device-access.rules
boot-files/
  panel.txt           panel identifier placed on FAT partition
local.env.example     copy to local.env and edit; gitignored
```

## Build system

- **Build host:** Alpine Linux x86_64 (also works on other distros with the right packages)
- **Cross-execution:** proot + qemu-aarch64 (not chroot — proot doesn't need root for the filesystem remapping)
- **No loop devices:** FAT built with mtools, ext4 root with `mkfs.ext4 -d`
- **Required host packages:** `bash curl qemu-aarch64 proot mtools squashfs-tools e2fsprogs dosfstools util-linux rsync xz cpio`

## Configuration

All settings live in `build/config.sh` with `${VAR:-default}` so env vars override them. Personal settings go in `local.env` (gitignored, never edit config.sh directly):

| Variable | Default | Notes |
|---|---|---|
| `PANEL` | `regular` | `regular` or `rev6` — check with `gpioget --bias=pull-up --chip /dev/gpiochip1 134` |
| `RAM_TYPE` | `DDR4` | `DDR4` or `DDR3` |
| `HOSTNAME` | `rg35xxh` | |
| `TIMEZONE` | `UTC` | |
| `ROOT_PASSWORD` | `root` | change before enabling SSH |
| `DEFAULT_USER` | `alpine` | |
| `DEFAULT_PASSWORD` | `alpine` | change before enabling SSH |
| `DEFAULT_USER_WHEEL` | `true` | adds user to wheel group |
| `ENABLE_SSH` | `true` | |
| `MAKE_GZ_IMAGE` | `true` | set false to skip xz compression during dev iteration |

## Key design decisions

- **No kernel compile.** ROCKNIX prebuilt kernel only.
- **iwd not wpa_supplicant.** Non-negotiable.
- **doas not sudo.**
- **eudev not mdev.** Alpine minirootfs ships with mdev; eudev is installed and mdev disabled. Wayland/DRM requires it.
- **Panel baked at build time.** No runtime detection daemon.
- **apk hook errors are harmless.** Post-install hooks call `unshare` which fails outside a real container. All packages install correctly. The build verifies each package explicitly after.
- **`apk fix` in chroot** replays unfired triggers so on-device `apk add` works cleanly. Requires DNS (proot shares host network, resolv.conf is bind-mounted in).

## Known issues / gotchas

- `apk fix` DNS may still fail if the build host's `/etc/resolv.conf` doesn't resolve Alpine CDN. Check with `curl -I https://dl-cdn.alpinelinux.org` from the host.
- Empty `DEFAULT_PASSWORD` may be rejected at login depending on PAM config. Set a password.
- Modules `sun4i-drm` and `panfrost` must be loaded for Wayland/sway to work. They're in `/etc/modules` so OpenRC loads them at boot.
- sway also needs elogind running and the user in the `video`, `input`, `render` groups — all handled at build time.
- `WLR_DRM_DEVICES=/dev/dri/card1` may be needed if wlroots picks the wrong card (card0 = display engine on this SoC, card1 = Mali).

## What's planned

- Configurable C input daemon: maps hardware buttons to keyboard/mouse events via uinput. Architecture discussed but not started. Will live in `src/inputd/`.
