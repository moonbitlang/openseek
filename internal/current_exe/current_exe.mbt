///|
/// Get current executable path
#cfg(platform="windows")
pub extern "c" fn current_exe() -> String = "moonbit_rt_get_current_exe"

///|
#cfg(not(platform="windows"))
extern "c" fn moonbit_rt_get_current_exe() -> Bytes = "moonbit_rt_get_current_exe"

///|
/// Get current executable path
#cfg(not(platform="windows"))
pub fn current_exe() -> String {
  @utf8.decode_lossy(moonbit_rt_get_current_exe())
}
