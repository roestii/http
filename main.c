#include <unistd.h>
#include <stdio.h>


int main(void) {
    int euid = geteuid();
    printf("effective user id: %d\n", euid);
    return 0;
}
