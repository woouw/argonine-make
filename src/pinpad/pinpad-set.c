/*
 * pinpad-set — set or change the ABXY button PIN
 *
 * Reads a button sequence from the gamepad (terminated by Start),
 * hashes it with yescrypt, and writes the hash to ~/.pinpad (0600).
 *
 * Usage: pinpad-set [/path/to/hashfile]
 *   Default hashfile: $HOME/.pinpad
 *
 * Build: cc -O2 -o pinpad-set pinpad-set.c -lcrypt
 */
#define _GNU_SOURCE
#include <crypt.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <pwd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "evdev.h"

#define MAX_PIN 64
#define HASHFILE_DEFAULT ".pinpad"

/* Read a button sequence into buf (NUL-terminated ABXY string).
 * Stops on Start (confirm) or when buf is full.
 * Returns length of sequence, or -1 on error. */
static int read_sequence(int gpfd, char *buf, int buflen)
{
    int len = 0;
    struct input_event ev;

    printf("Press ABXY buttons then START to confirm: ");
    fflush(stdout);

    while (len < buflen - 1) {
        ssize_t n = read(gpfd, &ev, sizeof(ev));
        if (n < (ssize_t)sizeof(ev)) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (ev.type != EV_KEY || ev.value != 1) continue; /* key-down only */

        int label = evdev_btn_to_label(ev.code);
        if (label == -1) {
            /* Start — confirm */
            break;
        }
        if (label == 0) continue; /* unrecognised button */

        buf[len++] = (char)label;
        putchar('*');
        fflush(stdout);
    }
    buf[len] = '\0';
    putchar('\n');
    return len;
}

/* Generate a yescrypt settings string with a random 16-byte salt */
static int make_settings(char *out, size_t outlen)
{
    uint8_t salt[16];
    if (getrandom(salt, sizeof(salt), 0) != (ssize_t)sizeof(salt)) {
        perror("getrandom");
        return -1;
    }

    /* crypt_gensalt_rn with yescrypt prefix "$y$" */
    char *s = crypt_gensalt_rn("$y$j9T$", /* cost N=2^14 */
                               0, (const char *)salt, sizeof(salt),
                               out, (int)outlen);
    if (!s) {
        fprintf(stderr, "crypt_gensalt_rn failed\n");
        return -1;
    }
    return 0;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "Usage: %s [hashfile]\n", argv0);
    fprintf(stderr, "  hashfile defaults to $HOME/" HASHFILE_DEFAULT "\n");
}

int main(int argc, char *argv[])
{
    const char *hashfile = NULL;
    char hashfile_buf[512];

    if (argc > 2) { usage(argv[0]); return 1; }
    if (argc == 2) {
        hashfile = argv[1];
    } else {
        const char *home = getenv("HOME");
        if (!home) {
            struct passwd *pw = getpwuid(getuid());
            home = pw ? pw->pw_dir : "/root";
        }
        snprintf(hashfile_buf, sizeof(hashfile_buf),
                 "%s/" HASHFILE_DEFAULT, home);
        hashfile = hashfile_buf;
    }

    int gpfd = evdev_open_gamepad();
    if (gpfd < 0) {
        fprintf(stderr, "pinpad-set: no gamepad found in /dev/input\n");
        return 1;
    }

    char pin1[MAX_PIN], pin2[MAX_PIN];

    /* First entry */
    int len1 = read_sequence(gpfd, pin1, sizeof(pin1));
    if (len1 <= 0) {
        fprintf(stderr, "pinpad-set: empty or failed sequence\n");
        close(gpfd);
        return 1;
    }

    /* Confirm */
    printf("Confirm PIN — ");
    int len2 = read_sequence(gpfd, pin2, sizeof(pin2));
    close(gpfd);

    if (len1 != len2 || memcmp(pin1, pin2, len1) != 0) {
        fprintf(stderr, "pinpad-set: sequences do not match\n");
        explicit_bzero(pin1, sizeof(pin1));
        explicit_bzero(pin2, sizeof(pin2));
        return 1;
    }
    explicit_bzero(pin2, sizeof(pin2));

    /* Hash */
    char settings[128];
    if (make_settings(settings, sizeof(settings)) < 0) {
        explicit_bzero(pin1, sizeof(pin1));
        return 1;
    }

    struct crypt_data cd;
    memset(&cd, 0, sizeof(cd));
    char *hash = crypt_r(pin1, settings, &cd);
    explicit_bzero(pin1, sizeof(pin1));

    if (!hash || hash[0] == '*') {
        fprintf(stderr, "pinpad-set: hashing failed\n");
        return 1;
    }

    /* Write atomically */
    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%s.tmp.%d", hashfile, (int)getpid());
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        perror(tmp);
        return 1;
    }
    dprintf(fd, "%s\n", hash);
    if (fsync(fd) < 0 || close(fd) < 0) {
        perror(tmp);
        unlink(tmp);
        return 1;
    }
    if (rename(tmp, hashfile) < 0) {
        perror(hashfile);
        unlink(tmp);
        return 1;
    }

    printf("PIN set. Hash written to %s\n", hashfile);
    return 0;
}
