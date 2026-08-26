#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <limits.h>

static void mark(const char *root, const char *name) {
    char path[PATH_MAX];
    if (snprintf(path, sizeof(path), "%s/%s", root, name) >= sizeof(path)) _exit(90);
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0 || write(fd, "observed", 8) != 8 || fsync(fd) != 0) _exit(91);
    close(fd);
}
static void pause_ms(int ms) { (void)poll(NULL, 0, ms); }
static void publish_child(const char *root, pid_t child) {
    char path[PATH_MAX], text[32];
    if (snprintf(path, sizeof(path), "%s/descendant.pid", root) >= sizeof(path)) _exit(98);
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    int count = snprintf(text, sizeof(text), "%d", child);
    if (fd < 0 || write(fd, text, count) != count || fsync(fd) != 0) _exit(98);
    close(fd);
}
static int observer_ready(const char *root) {
    char path[PATH_MAX];
    if (snprintf(path, sizeof(path), "%s/descendant-observed", root) >= sizeof(path)) return 0;
    for (int i = 0; i < 200; ++i) {
        if (access(path, F_OK) == 0) return 1;
        pause_ms(10);
    }
    return 0;
}
int main(int argc, char **argv) {
    if (argc != 3 || argv[2][0] != '/') return 92;
    if (!strcmp(argv[1], "exit-zero")) return 0;
    if (!strcmp(argv[1], "exit-seven")) return 7;
    if (!strcmp(argv[1], "coexist-seven")) { pause_ms(1500); return 7; }
    if (!strcmp(argv[1], "text")) {
        if (write(1, "out\n", 4) != 4 || write(2, "err\n", 4) != 4) return 93;
        return 0;
    }
    if (!strcmp(argv[1], "invalid-stdout")) {
        const unsigned char bad[] = { 0xC3, 0x28 };
        if (write(1, bad, sizeof(bad)) != sizeof(bad) || write(2, "err\n", 4) != 4) return 93;
        return 0;
    }
    if (!strcmp(argv[1], "invalid-stderr")) {
        const unsigned char bad[] = { 0xFF };
        if (write(1, "out\n", 4) != 4 || write(2, bad, sizeof(bad)) != sizeof(bad)) return 93;
        return 0;
    }
    if (!strcmp(argv[1], "flood")) {
        char bytes[4096]; memset(bytes, 'x', sizeof(bytes));
        for (int i = 0; i < 768; ++i) {
            if (write(1, bytes, sizeof(bytes)) != sizeof(bytes)) return 93;
            if (write(2, bytes, sizeof(bytes)) != sizeof(bytes)) return 94;
        }
        return 0;
    }
    if (!strcmp(argv[1], "orphan")) {
        pid_t child = fork();
        if (child < 0) return 95;
        if (child > 0) { publish_child(argv[2], child); return observer_ready(argv[2]) ? 0 : 99; }
        if (!observer_ready(argv[2])) return 99;
        mark(argv[2], "alive");
        pause_ms(1500); mark(argv[2], "done"); return 0;
    }
    if (!strcmp(argv[1], "gated")) {
        mark(argv[2], "ready");
        struct pollfd gate = { .fd = 0, .events = POLLIN };
        char byte = 0;
        if (poll(&gate, 1, 2000) <= 0 || read(0, &byte, 1) != 1 || byte != 'G') return 96;
        mark(argv[2], "effect");
        pause_ms(1200); mark(argv[2], "done"); return 0;
    }
    if (!strcmp(argv[1], "slow")) {
        mark(argv[2], "alive");
        pause_ms(1500); mark(argv[2], "done"); return 0;
    }
    return 97;
}

