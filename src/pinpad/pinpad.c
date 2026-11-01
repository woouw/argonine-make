/*
 * pinpad — gamepad PIN login gate
 *
 * Reads ~/.pinpad (yescrypt hash written by pinpad-set), prompts for
 * the ABXY button sequence, and on success exec's login(1) for the
 * current user so a proper PAM session is opened.
 *
 * Intended use: set as the shell in /etc/passwd for the autologin user,
 * or called from .bash_profile on TTY sessions:
 *
 *   agetty --autologin alpine tty1  →  /usr/local/bin/pinpad  →  bash
 *
 * On three consecutive failures a 30-second cooldown is enforced before
 * the next attempt. The cooldown resets on success.
 *
 * Build: cc -O2 -o pinpad pinpad.c -lcrypt
 */
#define _GNU_SOURCE
#include <crypt.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <pwd.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "evdev.h"

#define MAX_PIN       64
#define MAX_ATTEMPTS  3
#define COOLDOWN_SECS 30
#define HASHFILE      ".pinpad"

/* ------------------------------------------------------------------ */
/* TTY helpers                                                          */
/* ------------------------------------------------------------------ */

static void tty_clear(void)
{
    /* ANSI clear screen + cursor home */
    write(STDOUT_FILENO, "\033[2J\033[H", 7);
}

static void tty_hide_cursor(int hide)
{
    if (hide) write(STDOUT_FILENO, "\033[?25l", 6);
    else      write(STDOUT_FILENO, "\033[?25h", 6);
}

/* ------------------------------------------------------------------ */
/* Read hash from file                                                  */
/* ------------------------------------------------------------------ */

static int read_hashfile(const char *path, char *out, size_t outlen)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;

    /* Security: must be a regular file owned by current user, mode 0600 */
    struct stat st;
    if (fstat(fd, &st) < 0 || !S_ISREG(st.st_mode) ||
        st.st_uid != getuid() || (st.st_mode & 0077) != 0) {
        fprintf(stderr, "pinpad: %s has bad permissions — run pinpad-set\n", path);
        close(fd);
        return -1;
    }

    ssize_t n = read(fd, out, outlen - 1);
    close(fd);
    if (n <= 0) return -1;
    out[n] = '\0';
    /* Strip trailing newline */
    char *nl = strchr(out, '\n');
    if (nl) *nl = '\0';
    return 0;
}

/* ------------------------------------------------------------------ */
/* Read one button sequence from gamepad                               */
/* ------------------------------------------------------------------ */

static int read_sequence(int gpfd, char *buf, int buflen)
{
    int len = 0;
    struct input_event ev;

    while (len < buflen - 1) {
        ssize_t n = read(gpfd, &ev, sizeof(ev));
        if (n < (ssize_t)sizeof(ev)) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (ev.type != EV_KEY || ev.value != 1) continue;

        int label = evdev_btn_to_label(ev.code);
        if (label == -1) break;  /* Start = confirm */
        if (label == 0)  continue;

        buf[len++] = (char)label;
        putchar('*');
        fflush(stdout);
    }
    buf[len] = '\0';
    putchar('\n');
    return len;
}

/* ------------------------------------------------------------------ */
/* Cooldown display                                                     */
/* ------------------------------------------------------------------ */

static void cooldown(int secs)
{
    for (int i = secs; i > 0; i--) {
        tty_clear();
        printf("\n  Too many attempts. Wait %d second%s...\n",
               i, i == 1 ? "" : "s");
        fflush(stdout);
        sleep(1);
    }
}

/* ------------------------------------------------------------------ */
/* Main                                                                 */
/* ------------------------------------------------------------------ */

int main(void)
{
    /* Determine hashfile path */
    const char *home = getenv("HOME");
    struct passwd *pw = getpwuid(getuid());
    if (!home || home[0] == '\0')
        home = pw ? pw->pw_dir : "/root";

    char hashfile[512];
    snprintf(hashfile, sizeof(hashfile), "%s/" HASHFILE, home);

    /* If no hashfile exists, drop straight to shell (first boot / setup) */
    if (access(hashfile, F_OK) != 0) {
        fprintf(stderr,
            "pinpad: no PIN set — run pinpad-set to configure one\n"
            "pinpad: dropping to shell (run pinpad-set to enable PIN lock)\n");
        sleep(2);
        goto launch_shell;
    }

    char stored_hash[256];
    if (read_hashfile(hashfile, stored_hash, sizeof(stored_hash)) < 0) {
        fprintf(stderr, "pinpad: cannot read %s\n", hashfile);
        sleep(2);
        goto launch_shell;
    }

    int gpfd = evdev_open_gamepad();
    if (gpfd < 0) {
        fprintf(stderr, "pinpad: no gamepad found — dropping to shell\n");
        sleep(2);
        goto launch_shell;
    }

    tty_hide_cursor(1);

    int attempts = 0;

    for (;;) {
        tty_clear();
        printf("\n  ╔══════════════════════════╗\n");
        printf(  "  ║   Enter PIN (ABXY+START) ║\n");
        printf(  "  ╚══════════════════════════╝\n\n  ");
        fflush(stdout);

        char pin[MAX_PIN];
        int len = read_sequence(gpfd, pin, sizeof(pin));

        if (len <= 0) {
            explicit_bzero(pin, sizeof(pin));
            continue;
        }

        /* Hash and compare */
        struct crypt_data cd;
        memset(&cd, 0, sizeof(cd));
        char *hash = crypt_r(pin, stored_hash, &cd);
        explicit_bzero(pin, sizeof(pin));

        int ok = hash && strcmp(hash, stored_hash) == 0;
        explicit_bzero(&cd, sizeof(cd));

        if (ok) {
            tty_clear();
            tty_hide_cursor(0);
            close(gpfd);
            goto launch_shell;
        }

        attempts++;
        if (attempts >= MAX_ATTEMPTS) {
            tty_hide_cursor(0);
            cooldown(COOLDOWN_SECS);
            tty_hide_cursor(1);
            attempts = 0;
        } else {
            tty_clear();
            printf("\n  Wrong PIN (%d/%d)\n", attempts, MAX_ATTEMPTS);
            fflush(stdout);
            sleep(1);
        }
    }

launch_shell:;
    /* exec login -f <user> to get a proper PAM session */
    const char *user = pw ? pw->pw_name : getenv("USER");
    if (!user || user[0] == '\0') user = "alpine";

    execlp("login", "login", "-f", user, (char *)NULL);
    /* fallback: exec shell directly */
    const char *shell = pw ? pw->pw_shell : "/bin/sh";
    if (!shell || shell[0] == '\0') shell = "/bin/sh";
    execl(shell, shell, (char *)NULL);
    perror("exec");
    return 1;
}
