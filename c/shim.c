/* Cobolge byte-I/O shim — raw stdin/stdout/stderr for a Malbolge VM in COBOL.

   GnuCOBOL's runtime resolves C functions through the linker when the C
   source is compiled together with the COBOL module (cobc -x f.cob shim.c).
   The VM itself stays in COBOL; this shim only moves raw bytes across the
   process boundary, which COBOL's DISPLAY/ACCEPT cannot do faithfully.

   NOTE: Parameter types are `int` (32-bit) to match GnuCOBOL's `COMP-5`
   convention portably across both 64-bit Windows (LLP64) and Linux (LP64).
*/
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

/* put stdin/stdout/stderr in binary mode (Windows text mode would turn
   every newline written via putchar/fwrite into CRLF, corrupting the
   byte-exact Malbolge output stream) */
void cobinit(void) {
#ifdef _WIN32
    _setmode(_fileno(stdin),  _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
#endif
}

/* read one raw byte from stdin; return it (>=0), or -1 at EOF */
int cobgetc(void) {
    int c = getchar();
    return c;
}

/* write one raw byte to stdout */
int cobputc(int value) {
    int c = value & 0xFF;
    putchar(c);
    return 0;
}

/* write one raw byte to stderr (reports must not mix with program output) */
int cobpterr(int value) {
    int c = value & 0xFF;
    fputc(c, stderr);
    return 0;
}

/* flush stdout (used after writing program output, before any DISPLAY) */
void cobflush(void) {
    fflush(stdout);
}

/* write a block of `length` raw bytes to stdout; returns bytes written */
int cobwrite(const unsigned char *data, int length) {
    if (length <= 0) return 0;
    size_t w = fwrite(data, 1, (size_t)length, stdout);
    return (int)w;
}

/* write a block of `length` raw bytes to stderr; returns bytes written */
int cobwerr(const unsigned char *data, int length) {
    if (length <= 0) return 0;
    size_t w = fwrite(data, 1, (size_t)length, stderr);
    return (int)w;
}

/* read a whole file into buf (maxlen bytes); returns bytes read, or -1 */
int cobfread(const char *path, int pathlen, unsigned char *buf, int maxlen) {
    char tmp[1024];
    if (pathlen <= 0 || pathlen >= (int)sizeof(tmp)) return -1;
    memcpy(tmp, path, (size_t)pathlen);
    tmp[pathlen] = '\0';
    FILE *f = fopen(tmp, "rb");
    if (!f) return -1;
    int total = 0;
    int c;
    while (total < maxlen && (c = fgetc(f)) != EOF) {
        buf[total++] = (unsigned char)c;
    }
    fclose(f);
    return total;
}

/* write a whole file from buf (len bytes); returns 0 on success, -1 otherwise */
int cobfsave(const char *path, int pathlen, const unsigned char *buf, int len) {
    char tmp[1024];
    if (pathlen <= 0 || pathlen >= (int)sizeof(tmp)) return -1;
    memcpy(tmp, path, (size_t)pathlen);
    tmp[pathlen] = '\0';
    FILE *f = fopen(tmp, "wb");
    if (!f) return -1;
    size_t w = fwrite(buf, 1, (size_t)(len < 0 ? 0 : len), f);
    int e = fclose(f);
    if (e != 0 || (size_t)(len < 0 ? 0 : len) != w) return -1;
    return 0;
}
