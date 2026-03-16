#ifndef TALOS_HLS_STDIO_H_
#define TALOS_HLS_STDIO_H_

typedef struct talos_hls_file FILE;

extern FILE *stderr;

int printf(const char *fmt, ...);
int fprintf(FILE *stream, const char *fmt, ...);

#endif
