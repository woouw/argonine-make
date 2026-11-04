# Argonine

Argonine is an effort to make a handheld framework for computing.

This repo builds its base: Alpine Linux for Anbernic RG handhelds, turning the handheld into a pocket cyberdeck.

The base is not a new distro. It is a build system that assembles stock Alpine Linux for hardware nobody else supports properly: boot to a TTY, Wi-Fi (iwd) ready, `apk add` whatever you want. The hardware layer is borrowed from ROCKNIX; everything else is upstream Alpine.

**Supported devices:** RG35XX H (Allwinner H700). Other H700 RG devices differ mainly in their device tree and should be easy to add.

**Hardware layer:** kernel, U-Boot, device trees and firmware from [ROCKNIX](https://github.com/ROCKNIX/distribution) `20261001` (kernel 7.2).  
**Userspace:** Alpine Linux 3.24.3 (aarch64, musl).

## Before you build: find your panel

RG35XX H units have one of two screen panels. You need to know yours before building.

Boot any Linux on the device (e.g. Handtop) and run:

```sh
sudo gpioget --bias=pull-up --chip /dev/gpiochip1 134
```

- `"active"` → `PANEL=regular`
- `"inactive"` → `PANEL=rev6`

## Build

Build host packages: `bash`, `curl`, `qemu-aarch64`, `proot`, `mtools`, `squashfs-tools`, `e2fsprogs`, `dosfstools`, `util-linux` (for `sfdisk`), `rsync`, `xz`, and `cpio`.

```sh
# copy local.env.example to local.env first: set PANEL and unique passwords
# Do not keep the sample root/alpine passwords when SSH is enabled.
sudo bash build/build-all.sh
# → work/out/argonine-rg35xxh-regular-<date>.img.xz
```

For DDR3 units (rare):
```sh
sudo RAM_TYPE=DDR3 bash build/build-all.sh
```

## Flash

```sh
xzcat work/out/argonine-rg35xxh-*.img.xz | dd of=/dev/sdX bs=4M status=progress
```

Or use balenaEtcher / Rufus on the `.img.xz` directly.

Put the card in the **TF1** (left) slot and power on.

## First boot

Login with the username and password configured in `local.env` (defaults in `build/config.sh`). The sample defaults (`alpine/alpine` and `root/root`) are not safe to keep when SSH is enabled.  
Run `setup-alpine` to set timezone, locale, keymap etc.  
Wi-Fi: `iwctl` → `station wlan0 connect <SSID>`.

## Layout

```
build/          numbered build scripts + config
overlay/        files dropped into the rootfs
boot-files/     files placed on the FAT boot partition
```

## Companion projects

- **argonine-inputd** — gamepad/volume/power to keyboard + mouse daemon
- **argonine-locker** — button-sequence PIN lock/login (upcoming)
