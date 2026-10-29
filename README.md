# Alpine Linux for Anbernic RG35XX H

Boots Alpine Linux on the RG35XX H (Allwinner H700). Drops you at a TTY with Wi-Fi (iwd) ready to go. Build it yourself, flash it, `apk add` whatever you want.

**Hardware layer:** kernel, U-Boot, device trees and firmware from [ROCKNIX](https://github.com/ROCKNIX/distribution) `20261001` (kernel 7.2).  
**Userspace:** Alpine Linux 3.21 (aarch64, musl).

## Before you build: find your panel

RG35XX H units have one of two screen panels. You need to know yours before building.

Boot any Linux on the device (e.g. Handtop) and run:

```sh
sudo gpioget --bias=pull-up --chip /dev/gpiochip1 134
```

- `"active"` → `PANEL=regular`
- `"inactive"` → `PANEL=rev6`

## Build

Requires: `bash`, `curl`, `mtools`, `squashfs-tools`, `e2fsprogs`, `parted`, `xz`, `cpio`, `sfdisk`.

```sh
# edit build/config.sh first: set PANEL, ROOT_PASSWORD, DEFAULT_PASSWORD etc.
sudo bash build/build-all.sh
# → work/out/rg35xxh-alpine-regular-<date>.img.xz
```

For DDR3 units (rare):
```sh
sudo RAM_TYPE=DDR3 bash build/build-all.sh
```

## Flash

```sh
xzcat work/out/rg35xxh-alpine-*.img.xz | dd of=/dev/sdX bs=4M status=progress
```

Or use balenaEtcher / Rufus on the `.img.xz` directly.

Put the card in the **TF1** (left) slot and power on.

## First boot

Login: user `alpine`, password `alpine` (or whatever you set in `config.sh`).  
Run `setup-alpine` to set timezone, locale, keymap etc.  
Wi-Fi: `iwctl` → `station wlan0 connect <SSID>`.

## Layout

```
build/          numbered build scripts + config
overlay/        files dropped into the rootfs
boot-files/     files placed on the FAT boot partition
src/            (future) input daemon
```
