/*
 * OS cryptographic entropy for the gateway's access token and the relay's
 * device ids. moonbitlang/async's fs cannot open a character device like
 * /dev/urandom (its event loop rejects the non-regular fd), so the bytes are
 * read here with plain synchronous C: /dev/urandom on POSIX, rand_s on
 * Windows. Returns empty bytes on failure; the MoonBit side treats that as
 * "no entropy available" rather than inventing weak randomness.
 */

#include "moonbit.h"

#if defined(_WIN32)
#define _CRT_RAND_S
#include <stdlib.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

MOONBIT_FFI_EXPORT moonbit_bytes_t openseek_os_entropy(int32_t n) {
  if (n <= 0) {
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
#if defined(_WIN32)
  for (int32_t i = 0; i < n; i++) {
    unsigned int value;
    if (rand_s(&value) != 0) {
      return moonbit_make_bytes(0, 0);
    }
    out[i] = (uint8_t)(value & 0xff);
  }
#else
  int fd = open("/dev/urandom", O_RDONLY);
  if (fd < 0) {
    return moonbit_make_bytes(0, 0);
  }
  int32_t got = 0;
  while (got < n) {
    ssize_t r = read(fd, (char *)out + got, (size_t)(n - got));
    if (r <= 0) {
      close(fd);
      return moonbit_make_bytes(0, 0);
    }
    got += (int32_t)r;
  }
  close(fd);
#endif
  return out;
}
