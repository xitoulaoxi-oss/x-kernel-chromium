#include <stdio.h>
#include <time.h>

int main(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("clock_gettime");
        return 1;
    }
    printf("MONO %ld.%09ld\n", (long)ts.tv_sec, ts.tv_nsec);
    return 0;
}
