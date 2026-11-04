// Append-only log file for the desktop host's JSONL launch log.
//
// Each record is handed over as one complete line and written with a single
// append write: the file is opened with O_APPEND (FILE_APPEND_DATA on
// Windows), so the kernel positions every write at the current end of file
// and concurrent writers -- the host and its framework child process -- never
// overwrite or interleave each other's lines.

#include <stdint.h>
#include <stdlib.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#endif

typedef struct {
#ifdef _WIN32
  HANDLE handle;
#else
  int fd;
#endif
} openseek_log_file_t;

static int
openseek_log_file_is_open_impl(openseek_log_file_t *file) {
#ifdef _WIN32
  return file != NULL && file->handle != INVALID_HANDLE_VALUE;
#else
  return file != NULL && file->fd >= 0;
#endif
}

static void
openseek_log_file_finalize(void *ptr) {
  openseek_log_file_t *file = (openseek_log_file_t *)ptr;
  if (!openseek_log_file_is_open_impl(file)) {
    return;
  }
#ifdef _WIN32
  CloseHandle(file->handle);
  file->handle = INVALID_HANDLE_VALUE;
#else
  close(file->fd);
  file->fd = -1;
#endif
}

MOONBIT_FFI_EXPORT openseek_log_file_t *
openseek_log_file_open(moonbit_bytes_t path) {
  openseek_log_file_t *file =
    (openseek_log_file_t *)moonbit_make_external_object(
      openseek_log_file_finalize, sizeof(openseek_log_file_t));
#ifdef _WIN32
  file->handle = INVALID_HANDLE_VALUE;
  int wide_len =
    MultiByteToWideChar(CP_UTF8, 0, (const char *)path, -1, NULL, 0);
  if (wide_len <= 0) {
    return file;
  }
  wchar_t *wide = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)wide_len);
  if (wide == NULL) {
    return file;
  }
  MultiByteToWideChar(CP_UTF8, 0, (const char *)path, -1, wide, wide_len);
  file->handle = CreateFileW(
    wide, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  free(wide);
#else
  do {
    file->fd = open(
      (const char *)path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0644);
  } while (file->fd < 0 && errno == EINTR);
#endif
  return file;
}

MOONBIT_FFI_EXPORT int
openseek_log_file_is_open(openseek_log_file_t *file) {
  return openseek_log_file_is_open_impl(file);
}

// Write all of `data`. Returns 0 on success and -1 on failure.
MOONBIT_FFI_EXPORT int
openseek_log_file_append(openseek_log_file_t *file, moonbit_bytes_t data) {
  if (!openseek_log_file_is_open_impl(file)) {
    return -1;
  }
  const uint8_t *cursor = (const uint8_t *)data;
  size_t remaining = (size_t)Moonbit_array_length(data);
  while (remaining > 0) {
#ifdef _WIN32
    DWORD chunk = remaining > 0x40000000u ? 0x40000000u : (DWORD)remaining;
    DWORD written = 0;
    if (!WriteFile(file->handle, cursor, chunk, &written, NULL)) {
      return -1;
    }
#else
    ssize_t written = write(file->fd, cursor, remaining);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -1;
    }
#endif
    cursor += written;
    remaining -= (size_t)written;
  }
  return 0;
}
