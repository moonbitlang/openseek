///|
/// Installs the macOS main menu (App, Edit, and Window menus) on this
/// process's `NSApplication`. macOS dispatches command-key equivalents
/// through the main menu, and the embedded webview library never creates
/// one, so editing shortcuts like ⌘A/⌘C/⌘V are dropped without it. Must run
/// in the process that owns the webview, before its event loop starts.
/// No-op on other platforms, where the webview handles these shortcuts
/// natively.
pub extern "C" fn install_main_menu() -> Unit = "openseek_desktop_install_main_menu"
