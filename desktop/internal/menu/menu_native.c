/*
 * The macOS main menu. AppKit dispatches command-key equivalents (Select
 * All, Copy, Paste, ...) through the main menu's key equivalents, and the
 * embedded webview library never creates one, so without this menu those
 * shortcuts are silently dropped. The menu items target the first responder
 * (nil target), which lets the webview's own editing actions handle them.
 *
 * The Objective-C runtime functions are declared by hand instead of
 * including the objc headers so the stub compiles under minimal C
 * compilers; linking needs `-lobjc -framework AppKit`, which
 * native_link_config.mjs adds on darwin.
 */

#include "moonbit.h"

#if defined(__APPLE__)

#include <stddef.h>

typedef void *imp_t;

extern imp_t objc_getClass(const char *name);
extern imp_t sel_registerName(const char *name);
extern void objc_msgSend(void);

typedef imp_t (*send_t)(imp_t, imp_t);
typedef imp_t (*send_id_t)(imp_t, imp_t, imp_t);
typedef imp_t (*send_cstr_t)(imp_t, imp_t, const char *);
typedef imp_t (*send_item_t)(imp_t, imp_t, imp_t, imp_t, imp_t);
typedef void (*send_void_id_t)(imp_t, imp_t, imp_t);
typedef void (*send_void_id_id_t)(imp_t, imp_t, imp_t, imp_t);
typedef void (*send_void_ulong_t)(imp_t, imp_t, unsigned long);

enum {
  modifier_option = 1ul << 19,
  modifier_command = 1ul << 20,
};

static imp_t ns_string(const char *utf8) {
  return ((send_cstr_t)objc_msgSend)(
      objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
      utf8);
}

static imp_t new_menu(const char *title) {
  imp_t menu =
      ((send_t)objc_msgSend)(objc_getClass("NSMenu"), sel_registerName("alloc"));
  return ((send_id_t)objc_msgSend)(menu, sel_registerName("initWithTitle:"),
                                   ns_string(title));
}

static imp_t add_item(imp_t menu, const char *title, const char *action,
                      const char *key) {
  return ((send_item_t)objc_msgSend)(
      menu, sel_registerName("addItemWithTitle:action:keyEquivalent:"),
      ns_string(title), action == NULL ? NULL : sel_registerName(action),
      ns_string(key));
}

static void add_separator(imp_t menu) {
  imp_t separator = ((send_t)objc_msgSend)(objc_getClass("NSMenuItem"),
                                           sel_registerName("separatorItem"));
  ((send_void_id_t)objc_msgSend)(menu, sel_registerName("addItem:"), separator);
}

static void attach_submenu(imp_t main_menu, imp_t submenu) {
  imp_t item = add_item(main_menu, "", NULL, "");
  ((send_void_id_id_t)objc_msgSend)(
      main_menu, sel_registerName("setSubmenu:forItem:"), submenu, item);
}

MOONBIT_FFI_EXPORT void openseek_desktop_install_main_menu(void) {
  imp_t main_menu = new_menu("");

  imp_t app_menu = new_menu("OpenSeek Desktop");
  add_item(app_menu, "Hide OpenSeek Desktop", "hide:", "h");
  imp_t hide_others =
      add_item(app_menu, "Hide Others", "hideOtherApplications:", "h");
  ((send_void_ulong_t)objc_msgSend)(
      hide_others, sel_registerName("setKeyEquivalentModifierMask:"),
      modifier_command | modifier_option);
  add_item(app_menu, "Show All", "unhideAllApplications:", "");
  add_separator(app_menu);
  add_item(app_menu, "Quit OpenSeek Desktop", "terminate:", "q");
  attach_submenu(main_menu, app_menu);

  imp_t edit_menu = new_menu("Edit");
  add_item(edit_menu, "Undo", "undo:", "z");
  /* An uppercase key equivalent implies the Shift modifier. */
  add_item(edit_menu, "Redo", "redo:", "Z");
  add_separator(edit_menu);
  add_item(edit_menu, "Cut", "cut:", "x");
  add_item(edit_menu, "Copy", "copy:", "c");
  add_item(edit_menu, "Paste", "paste:", "v");
  add_item(edit_menu, "Select All", "selectAll:", "a");
  attach_submenu(main_menu, edit_menu);

  imp_t window_menu = new_menu("Window");
  add_item(window_menu, "Minimize", "performMiniaturize:", "m");
  add_item(window_menu, "Zoom", "performZoom:", "");
  add_item(window_menu, "Close", "performClose:", "w");
  attach_submenu(main_menu, window_menu);

  imp_t app = ((send_t)objc_msgSend)(objc_getClass("NSApplication"),
                                     sel_registerName("sharedApplication"));
  ((send_void_id_t)objc_msgSend)(app, sel_registerName("setMainMenu:"),
                                 main_menu);
  ((send_void_id_t)objc_msgSend)(app, sel_registerName("setWindowsMenu:"),
                                 window_menu);
}

#else

MOONBIT_FFI_EXPORT void openseek_desktop_install_main_menu(void) {}

#endif
