#include <curses.h>
#include <stdio.h>
#include <term.h>
#include <unistd.h>

int main(int argc, char **argv) {
  int status;
  if (argc != 2 || setupterm(argv[1], STDOUT_FILENO, &status) != OK) {
    fprintf(stderr, "missing embedded terminfo for %s\n", argc == 2 ? argv[1] : "(unspecified)");
    return 1;
  }
  char *cursor = tigetstr("cup");
  if (!cursor || cursor == (char *)-1) {
    fprintf(stderr, "missing cursor addressing for %s\n", argv[1]);
    return 1;
  }
  printf("embedded terminfo: %s\n", argv[1]);
  return 0;
}
