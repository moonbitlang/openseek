/* The host's C runtime owns local timezone conversion, including DST rules. */
#include <stdint.h>
#include <time.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT int32_t
openseek_schedule_local_parts(int64_t seconds, int32_t *parts) {
#ifdef _WIN32
  _tzset();
#else
  tzset();
#endif
  time_t instant = (time_t)seconds;
  struct tm local;
#ifdef _WIN32
  if (localtime_s(&local, &instant) != 0) return 0;
#else
  if (localtime_r(&instant, &local) == NULL) return 0;
#endif
  parts[0] = local.tm_year + 1900;
  parts[1] = local.tm_mon + 1;
  parts[2] = local.tm_mday;
  parts[3] = local.tm_hour;
  parts[4] = local.tm_min;
  return 1;
}

MOONBIT_FFI_EXPORT int32_t
openseek_schedule_local_instant(int32_t year, int32_t month, int32_t day,
                               int32_t hour, int32_t minute, int32_t dst,
                               int64_t *result) {
  struct tm local = {0};
  local.tm_year = year - 1900;
  local.tm_mon = month - 1;
  local.tm_mday = day;
  local.tm_hour = hour;
  local.tm_min = minute;
  local.tm_isdst = dst;
  time_t instant = mktime(&local);
  if (instant == (time_t)-1) return 0;
  result[0] = (int64_t)instant;
  return 1;
}
