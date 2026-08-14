/*
 * Small native integrations owned by the desktop host. The MoonBit wrappers
 * select the Windows paths; keeping the stubs buildable elsewhere lets the
 * package retain one native configuration.
 */

#include <stdint.h>

#include "moonbit.h"

#if defined(_WIN32)

#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <shellapi.h>

#if !defined(_MSC_VER)
#error "SeekMoon's Windows desktop host requires an MSVC-compatible compiler"
#endif

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(linker, "/SUBSYSTEM:WINDOWS")
#pragma comment(linker, "/ENTRY:mainCRTStartup")

#define OPENSEEK_DWMWA_USE_IMMERSIVE_DARK_MODE 20
#define OPENSEEK_DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 19
#define OPENSEEK_TITLEBAR_SUBCLASS_ID 0x53454B4D

typedef struct openseek_window_search {
  DWORD process_id;
  HWND window;
} openseek_window_search_t;

static BOOL CALLBACK openseek_find_main_window(HWND window, LPARAM data) {
  openseek_window_search_t *search = (openseek_window_search_t *)data;
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id != search->process_id || !IsWindowVisible(window) ||
      GetWindow(window, GW_OWNER) != NULL ||
      (GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) {
    return TRUE;
  }
  search->window = window;
  return FALSE;
}

static HWND openseek_main_window(void) {
  const DWORD process_id = GetCurrentProcessId();
  HWND window = GetForegroundWindow();
  DWORD foreground_process_id = 0;
  if (window != NULL) {
    GetWindowThreadProcessId(window, &foreground_process_id);
    if (foreground_process_id == process_id &&
        GetWindow(window, GW_OWNER) == NULL) {
      return window;
    }
  }
  openseek_window_search_t search = {
      .process_id = process_id,
      .window = NULL,
  };
  EnumWindows(openseek_find_main_window, (LPARAM)&search);
  return search.window;
}

static HRESULT openseek_apply_titlebar_dark_mode(HWND window, BOOL dark) {
  HRESULT result = DwmSetWindowAttribute(
      window, OPENSEEK_DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
  if (FAILED(result)) {
    result = DwmSetWindowAttribute(
        window, OPENSEEK_DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1, &dark,
        sizeof(dark));
  }
  if (SUCCEEDED(result)) {
    RedrawWindow(window, NULL, NULL,
                 RDW_FRAME | RDW_INVALIDATE | RDW_UPDATENOW);
  }
  return result;
}

static LRESULT CALLBACK openseek_titlebar_subclass(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR data) {
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, openseek_titlebar_subclass, subclass_id);
    return DefSubclassProc(window, message, wparam, lparam);
  }
  LRESULT result = DefSubclassProc(window, message, wparam, lparam);
  if (message == WM_ACTIVATE || message == WM_DPICHANGED ||
      message == WM_THEMECHANGED || message == WM_SETTINGCHANGE) {
    (void)openseek_apply_titlebar_dark_mode(window, data != 0);
  }
  return result;
}

#endif

MOONBIT_FFI_EXPORT int32_t
moonbit_openseek_desktop_platform_set_titlebar_dark_mode(int32_t dark) {
#if defined(_WIN32)
  HWND window = openseek_main_window();
  if (window == NULL) {
    return 1;
  }
  if (!SetWindowSubclass(window, openseek_titlebar_subclass,
                         OPENSEEK_TITLEBAR_SUBCLASS_ID,
                         dark != 0 ? 1 : 0)) {
    return 2;
  }
  return SUCCEEDED(
             openseek_apply_titlebar_dark_mode(window, dark != 0 ? TRUE : FALSE))
             ? 0
             : 3;
#else
  (void)dark;
  return 0;
#endif
}

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
