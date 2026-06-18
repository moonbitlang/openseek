/*
 * The user's Documents folder as the platform knows it. Only Windows has a
 * native authority worth asking (the Documents known folder, which OneDrive's
 * folder move or group policy may relocate). Everywhere else the MoonBit side
 * resolves the answer itself, so this file exports the FFI symbol only on
 * Windows.
 */

#include <string.h>

#include "moonbit.h"

#if defined(_WIN32)

#include <windows.h>
#include <initguid.h>
#include <knownfolders.h>
#include <shlobj.h>
#ifdef _MSC_VER
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#endif

/* The known-folder path as UTF-8, or empty bytes when the lookup fails. */
MOONBIT_FFI_EXPORT moonbit_bytes_t openseek_desktop_documents_dir(void) {
  moonbit_bytes_t result = NULL;
  PWSTR wide = NULL;
  if (SHGetKnownFolderPath(&FOLDERID_Documents, KF_FLAG_DONT_VERIFY, NULL,
                           &wide) == S_OK) {
    int wide_length = lstrlenW(wide);
    int size = WideCharToMultiByte(CP_UTF8, 0, wide, wide_length, NULL, 0,
                                   NULL, NULL);
    if (size > 0) {
      result = moonbit_make_bytes(size, 0);
      WideCharToMultiByte(CP_UTF8, 0, wide, wide_length, (char *)result, size,
                          NULL, NULL);
    }
  }
  /* Documented contract: free the buffer even when the call fails. */
  CoTaskMemFree(wide);
  if (result == NULL) {
    result = moonbit_make_bytes(0, 0);
  }
  return result;
}

#endif
