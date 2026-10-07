/*
 * Optional E70Q10 suspend/battery recorder.  Remove this directory, its
 * PRODUCT_PACKAGES entry, and the init service to remove the whole feature.
 * The process holds no wake lock and uses CLOCK_MONOTONIC for its timer, so
 * its timer does not count down or wake the device while it is suspended.
 */
#define _POSIX_C_SOURCE 200809L
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define LOG_DIR "/data/ridi/logs/power-diag"
#define LOG_PATH LOG_DIR "/samples.log"
#define OLD_PATH LOG_DIR "/samples.previous.log"
#define PID_PATH LOG_DIR "/recorder.pid"
#define MAX_LOG_BYTES (16 * 1024 * 1024)
#define SAMPLE_SECONDS 60
#define MAX_SOURCE_BYTES (256 * 1024)

static volatile sig_atomic_t stop_requested;
static volatile sig_atomic_t sample_requested;
static char session_id[64];

static void handle_signal(int signum) {
    if (signum == SIGTERM || signum == SIGINT) stop_requested = 1;
    if (signum == SIGUSR1) sample_requested = 1;
}

static double seconds_for(clockid_t clock_id) {
    struct timespec value;
    if (clock_gettime(clock_id, &value) != 0) return -1.0;
    return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}

static void append_source(FILE *log, const char *path) {
    char buffer[4096];
    size_t total = 0;
    FILE *source;
    fprintf(log, "--- %s ---\n", path);
    source = fopen(path, "r");
    if (!source) {
        fprintf(log, "unavailable: %s\n", strerror(errno));
        return;
    }
    while (!feof(source) && total < MAX_SOURCE_BYTES) {
        size_t available = sizeof(buffer);
        size_t read_count;
        if (available > MAX_SOURCE_BYTES - total) available = MAX_SOURCE_BYTES - total;
        read_count = fread(buffer, 1, available, source);
        if (read_count == 0) break;
        fwrite(buffer, 1, read_count, log);
        total += read_count;
    }
    if (total >= MAX_SOURCE_BYTES) fputs("\n[truncated]\n", log);
    else fputc('\n', log);
    fclose(source);
}

static void append_power_supplies(FILE *log) {
    const char *directory = "/sys/class/power_supply";
    struct dirent *entry;
    DIR *supplies = opendir(directory);
    if (!supplies) {
        fprintf(log, "--- %s ---\nunavailable: %s\n", directory, strerror(errno));
        return;
    }
    while ((entry = readdir(supplies)) != NULL) {
        char path[512];
        int length;
        if (entry->d_name[0] == '.') continue;
        length = snprintf(path, sizeof(path), "%s/%s/uevent", directory, entry->d_name);
        if (length > 0 && (size_t)length < sizeof(path)) append_source(log, path);
    }
    closedir(supplies);
}

static void rotate_if_needed(void) {
    struct stat info;
    if (stat(LOG_PATH, &info) == 0 && info.st_size >= MAX_LOG_BYTES) {
        unlink(OLD_PATH);
        rename(LOG_PATH, OLD_PATH);
    }
}

static void take_sample(const char *reason) {
    static unsigned int sequence;
    FILE *log;
    time_t now;
    struct tm local;
    char wall[64] = "unknown";

    rotate_if_needed();
    log = fopen(LOG_PATH, "a");
    if (!log) return;
    now = time(NULL);
    if (localtime_r(&now, &local) != NULL)
        strftime(wall, sizeof(wall), "%Y-%m-%dT%H:%M:%S%z", &local);
    fprintf(log, "=== SAMPLE seq=%u session=%s reason=%s wall=%s boottime=%.3f monotonic=%.3f ===\n",
            ++sequence, session_id, reason, wall, seconds_for(CLOCK_BOOTTIME),
            seconds_for(CLOCK_MONOTONIC));
    append_source(log, "/proc/sys/kernel/random/boot_id");
    append_source(log, "/sys/kernel/debug/wakeup_sources");
    append_source(log, "/sys/kernel/debug/suspend_stats");
    append_source(log, "/sys/kernel/wakeup_reasons/last_resume_reason");
    append_source(log, "/sys/kernel/wakeup_reasons/last_suspend_time");
    append_source(log, "/proc/stat");
    append_power_supplies(log);
    fputs("=== END SAMPLE ===\n", log);
    fclose(log);
}

/* BatteryStats -c reads current UID data without clearing existing stats. */
static void capture_framework_stats(const char *suffix) {
    char path[256];
    pid_t child;
    int status;
    int length = snprintf(path, sizeof(path), LOG_DIR "/batterystats-%s.txt", suffix);
    if (length <= 0 || (size_t)length >= sizeof(path)) return;
    child = fork();
    if (child == 0) {
        int output = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (output < 0) _exit(1);
        if (dup2(output, STDOUT_FILENO) < 0) _exit(1);
        close(output);
        execl("/system/bin/dumpsys", "dumpsys", "batterystats", "-c", (char *)NULL);
        _exit(127);
    }
    if (child > 0) {
        while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
        }
    }
}

int main(void) {
    FILE *pid_file;
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = handle_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGUSR1, &action, NULL);
    if (mkdir(LOG_DIR, 0700) != 0 && errno != EEXIST) return 1;
    snprintf(session_id, sizeof(session_id), "%ld-%ld",
            (long)time(NULL), (long)getpid());
    pid_file = fopen(PID_PATH, "w");
    if (pid_file != NULL) {
        fprintf(pid_file, "%ld\n", (long)getpid());
        fclose(pid_file);
    }
    unlink(LOG_DIR "/batterystats-end.txt");
    take_sample("start");
    capture_framework_stats("start");
    while (!stop_requested) {
        struct timespec remaining = { SAMPLE_SECONDS, 0 };
        while (!stop_requested && !sample_requested
                && nanosleep(&remaining, &remaining) == -1 && errno == EINTR) {
            /* Resume the remaining awake-time interval after other signals. */
        }
        if (stop_requested) break;
        if (sample_requested) {
            take_sample("requested");
            capture_framework_stats("end");
        } else {
            take_sample("interval");
        }
        sample_requested = 0;
    }
    take_sample("stop");
    capture_framework_stats("end");
    unlink(PID_PATH);
    return 0;
}
