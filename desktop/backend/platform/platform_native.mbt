///|
/// Hand one UTF-16 target to the native opener. The C stub calls
/// `ShellExecuteW` on Windows and returns failure elsewhere; the public
/// wrappers only select it on Windows. MoonBit strings are NUL-terminated
/// UTF-16 on the native backend, which is exactly what `ShellExecuteW`
/// consumes, so no command interpreter sees the target.
#borrow(target)
extern "C" fn windows_open(target : String) -> Int32 = "moonbit_openseek_desktop_platform_open"

///|
/// Ask Explorer to show and select one path without routing it through a
/// command interpreter. The non-Windows stub fails closed; the public wrapper
/// selects it only on Windows.
#borrow(target)
extern "C" fn windows_reveal(target : String) -> Int32 = "moonbit_openseek_desktop_platform_reveal"
