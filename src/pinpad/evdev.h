/* evdev.h — minimal evdev helpers for pinpad */
#pragma once
#include <linux/input.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Button labels used for display and PIN string encoding */
#define BTN_LABEL_A  'A'
#define BTN_LABEL_B  'B'
#define BTN_LABEL_X  'X'
#define BTN_LABEL_Y  'Y'

/*
 * Map a kernel button code to an ABXY character.
 * Returns 0 if the code is not one of the four face buttons.
 * Returns -1 if the code is the confirm button (BTN_START).
 *
 * The RG35XX H uses the standard gamepad BTN_* codes from
 * linux/input-event-codes.h:
 *   BTN_SOUTH = A, BTN_EAST = B, BTN_NORTH = Y, BTN_WEST = X
 *   BTN_START = confirm / submit
 */
static inline int evdev_btn_to_label(unsigned int code)
{
    switch (code) {
    case BTN_SOUTH: return BTN_LABEL_A;
    case BTN_EAST:  return BTN_LABEL_B;
    case BTN_WEST:  return BTN_LABEL_X;
    case BTN_NORTH: return BTN_LABEL_Y;
    case BTN_START: return -1;  /* confirm */
    default:        return 0;   /* ignore */
    }
}

/*
 * Find the first event device that has BTN_SOUTH (face buttons).
 * Returns an open fd or -1 on failure.
 */
static inline int evdev_open_gamepad(void)
{
    DIR *d = opendir("/dev/input");
    if (!d) return -1;

    struct dirent *e;
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "event", 5) != 0) continue;

        char path[64];
        snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        /* Check for BTN_SOUTH in the key bitmask */
        unsigned long bits[BTN_MAX / (8 * sizeof(unsigned long)) + 1];
        memset(bits, 0, sizeof(bits));
        if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) >= 0) {
            unsigned int word = BTN_SOUTH / (8 * sizeof(unsigned long));
            unsigned int bit  = BTN_SOUTH % (8 * sizeof(unsigned long));
            if (bits[word] & (1UL << bit)) {
                closedir(d);
                /* reopen blocking for read() */
                close(fd);
                fd = open(path, O_RDONLY);
                return fd;
            }
        }
        close(fd);
    }
    closedir(d);
    return -1;
}
