#include <stdio.h>
#include <string.h>

// Stub command handler
int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command> [...]\n", argv[0]);
        return 1;
    }
    if (strcmp(argv[1], "type") == 0) {
        printf("Typing text: %s\n", argv[2]);
    } else if (strcmp(argv[1], "move") == 0) {
        printf("Moving mouse by %s, %s\n", argv[2], argv[3]);
    } else if (strcmp(argv[1], "click") == 0) {
        printf("Clicking %s button\n", argv[2]);
    }
    return 0;
}
