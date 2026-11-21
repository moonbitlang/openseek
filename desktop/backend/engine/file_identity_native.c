/*
 * Linux file identity lookup (device and inode) for the listing prompt cache.
 * Linux filesystem timestamps advance on coarse clock ticks (1-4 ms), so
 * atomic temp-file rewrites within one tick can keep identical (mtime, ctime)
 * and size. Each atomic rewrite allocates a new inode, so comparing (dev, ino)
 * invalidates stale entries without waiting on timers.
 * macOS (nanosecond APFS) and Windows (100ns NTFS) bypass this lookup.
 */

#include <stdint.h>

#include "moonbit.h"

#if defined(__linux__)
#include <sys/stat.h>
#endif

MOONBIT_FFI_EXPORT int32_t moonbit_openseek_desktop_engine_file_identity(
    moonbit_bytes_t path_utf8, uint64_t *out) {
#if defined(__linux__)
  if (path_utf8 == NULL || out == NULL) {
    return -1;
  }
  int32_t path_len = Moonbit_array_length(path_utf8);
  if (path_len <= 0 || path_utf8[path_len - 1] != 0) {
    return -1;
  }
  if (Moonbit_array_length(out) < 2) {
    return -1;
  }
  struct stat st;
  if (stat((const char *)path_utf8, &st) != 0) {
    return -1;
  }
  out[0] = (uint64_t)st.st_dev;
  out[1] = (uint64_t)st.st_ino;
  return 0;
#else
  (void)path_utf8;
  (void)out;
  return -1;
#endif
}
