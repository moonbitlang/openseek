/*
 * Open a URL or filesystem path with the operating system's registered
 * handler. The MoonBit wrapper calls this only on Windows; keeping the stub
 * buildable elsewhere lets the package retain one native configuration.
 */

#include <stdint.h>

#include "moonbit.h"

#if defined(_WIN32)

#include <shellapi.h>
#include <windows.h>

#if defined(_MSC_VER)
#pragma comment(lib, "shell32.lib")
#endif

#endif

MOONBIT_FFI_EXPORT int32_t
moonbit_openseek_desktop_platform_open(moonbit_string_t target) {
#if defined(_WIN32)
  /*
   * ShellExecuteW receives the target as data. In particular, characters such
   * as '&' and '|' never pass through cmd.exe and cannot become commands.
   */
  INT_PTR result =
      (INT_PTR)ShellExecuteW(NULL, L"open", (const wchar_t *)target, NULL, NULL,
                            SW_SHOWNORMAL);
  if (result > 32) {
    return 0;
  }
  /* ShellExecuteW may report failure as zero; preserve non-zero exit semantics. */
  return result == 0 ? 1 : (int32_t)result;
#else
  (void)target;
  return 1;
#endif
}
