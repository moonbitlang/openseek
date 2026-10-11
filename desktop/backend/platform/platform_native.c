/*
 * Small native integrations owned by the desktop host. The MoonBit wrappers
 * select the Windows paths; keeping the stubs buildable elsewhere lets the
 * package retain one native configuration.
 */

#include <stdint.h>

#include "moonbit.h"

#if defined(_WIN32)

#include <windows.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>

#if !defined(_MSC_VER)
#error "SeekMoon's Windows desktop host requires an MSVC-compatible compiler"
#endif

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(linker, "/SUBSYSTEM:WINDOWS")
#pragma comment(linker, "/ENTRY:mainCRTStartup")

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

MOONBIT_FFI_EXPORT int32_t
moonbit_openseek_desktop_platform_reveal(moonbit_string_t target) {
#if defined(_WIN32)
  /*
   * Work with PIDLs instead of building an explorer.exe command line. This
   * preserves spaces and punctuation as path data and selects the target in
   * its parent directory, matching Finder's `open -R` behavior.
   */
  HRESULT com = CoInitializeEx(
      NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(com) && com != RPC_E_CHANGED_MODE) {
    return 1;
  }
  const BOOL uninitialize_com = SUCCEEDED(com);
  PIDLIST_ABSOLUTE item = ILCreateFromPathW((const wchar_t *)target);
  PIDLIST_ABSOLUTE parent = item == NULL ? NULL : ILCloneFull(item);
  HRESULT result = E_FAIL;
  if (parent != NULL) {
    PCUITEMID_CHILD child = ILFindLastID(item);
    if (child != NULL && child->mkid.cb != 0 && ILRemoveLastID(parent)) {
      result = SHOpenFolderAndSelectItems(parent, 1, &child, 0);
    } else {
      /* A filesystem root has no selectable child; opening it is the closest
         meaningful file-manager action. */
      INT_PTR opened = (INT_PTR)ShellExecuteW(
          NULL, L"open", (const wchar_t *)target, NULL, NULL, SW_SHOWNORMAL);
      if (opened > 32) {
        result = S_OK;
      }
    }
  }
  if (parent != NULL) {
    ILFree(parent);
  }
  if (item != NULL) {
    ILFree(item);
  }
  if (uninitialize_com) {
    CoUninitialize();
  }
  return SUCCEEDED(result) ? 0 : 1;
#else
  (void)target;
  return 1;
#endif
}
