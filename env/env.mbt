///|
/// Return the current program's executable path.
///
/// On native targets this is the OS-reported executable path. On linear Wasm
/// it is the absolute module path captured by moonrun when the file was loaded,
/// not the moonrun executable or `args()[0]`.
///
/// Raises `OSError` if the runtime cannot provide a path, including execution
/// without a file origin. Symlink resolution and behavior after renaming or
/// deleting the executable follow the runtime. Native path decoding may be lossy;
/// the result is not guaranteed to round-trip arbitrary OS filenames.
pub fn current_exe() -> String raise @os_error.OSError {
  current_exe_internal()
}

///|
/// Return the directory containing the current program's executable.
///
/// Uses the same runtime path and error behavior as `current_exe`. This does
/// not check that the directory still exists or resolve it through symlinks.
pub fn current_exe_dir() -> String raise @os_error.OSError {
  current_exe_dir_internal()
}
