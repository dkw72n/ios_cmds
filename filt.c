#include <stdio.h>
#include <string.h>

int main(int argc, char** argv)
{
  char buf[2048];
  char* line;
  while((line = fgets(buf, 2048, stdin))){
    int print = 1;
    for(int i = 1; i < argc; ++i){
      const char* ptn = argv[i];
      int exclude = 0;
      if (ptn[0] == '-' || ptn[0] == '+') {
        exclude = ptn[0] == '-';
        ptn++;
      }
      if (exclude){
        if (strstr(line, ptn)){
          print = 0;
          break;
        }
      } else {
        if (!strstr(line, ptn)){
          print = 0;
          break;
        }
      }
    }
    if (print){
      fputs(line, stdout);
    }
  }
  return 0;
}
