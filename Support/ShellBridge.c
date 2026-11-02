#include <util.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>
#include <poll.h>
#include <sys/wait.h>
#include <errno.h>
#include <string.h>
static volatile sig_atomic_t stopping = 0;
static void stop_handler(int signal_number) { (void)signal_number; stopping = 1; }
static int write_all(int fd, const char *data, ssize_t count) {
    while (count > 0) {
        ssize_t n = write(fd, data, (size_t)count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        count -= n; data += n;
    }
    return 0;
}
int main(void) {
    int master = -1;
    struct winsize size = {28, 100, 0, 0};
    pid_t child = forkpty(&master, NULL, NULL, &size);
    if (child < 0) return 126;
    if (child == 0) { execl("/bin/zsh", "zsh", "-f", "-o", "no_zle", "-o", "no_prompt_sp", (char *)NULL); _exit(127); }
    signal(SIGTERM, stop_handler); signal(SIGINT, stop_handler); signal(SIGHUP, stop_handler); signal(SIGPIPE, SIG_IGN);
    struct pollfd fds[2] = {{STDIN_FILENO, POLLIN, 0}, {master, POLLIN, 0}};
    char bytes[16384];
    while (!stopping) {
        int ready = poll(fds, 2, 200);
        if (ready < 0) { if (errno == EINTR) continue; break; }
        if (fds[0].revents & (POLLIN | POLLHUP)) {
            ssize_t n = read(STDIN_FILENO, bytes, sizeof(bytes));
            if (n <= 0 || write_all(master, bytes, n) < 0) break;
        }
        if (fds[1].revents & (POLLIN | POLLHUP | POLLERR)) {
            ssize_t n = read(master, bytes, sizeof(bytes));
            if (n <= 0 || write_all(STDOUT_FILENO, bytes, n) < 0) break;
        }
    }
    close(master);
    kill(-child, SIGHUP); kill(child, SIGHUP);
    int status = 0;
    for (int i=0;i<20;i++) { if (waitpid(child, &status, WNOHANG) == child) return 0; usleep(50000); }
    kill(-child, SIGKILL); kill(child, SIGKILL); waitpid(child, &status, 0);
    return 0;
}
