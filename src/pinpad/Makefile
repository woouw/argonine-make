# pinpad — ABXY gamepad PIN login gate
# Cross-compile for aarch64-alpine-musl or build natively on the device.
#
# Host build (requires aarch64 cross toolchain):
#   make CC=aarch64-linux-musl-gcc
#
# On-device build (Alpine):
#   apk add build-base libxcrypt-dev
#   make

CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11
LDFLAGS ?= -lcrypt

TARGETS = pinpad pinpad-set

.PHONY: all clean install

all: $(TARGETS)

pinpad: pinpad.c evdev.h
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

pinpad-set: pinpad-set.c evdev.h
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

install: $(TARGETS)
	install -Dm755 pinpad     $(DESTDIR)/usr/local/bin/pinpad
	install -Dm755 pinpad-set $(DESTDIR)/usr/local/bin/pinpad-set

clean:
	rm -f $(TARGETS)
