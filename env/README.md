# Executable paths

Import `bobzhang/openseek/env` to locate the running program:

```moonbit
import {
  "bobzhang/openseek/env" @exe,
}
```

Both `@exe.current_exe()` and `@exe.current_exe_dir()` return `String` and
raise `OSError` from `moonbitlang/async/os_error` when the runtime cannot supply a path.
They never fall back to the working directory or command-line arguments.

Supported targets:

- **Native:** uses the toolchain's `moonbit_rt_get_current_exe` hook and derives
  its directory with `moonbitlang/x/path`. Failures preserve `errno` or the
  Windows last-error code.
- **Linear Wasm:** requires moonrun's `moonbitlang/core` imports
  `env/current_exe` and `env/current_exe_dir`. These identify the loaded Wasm
  file, with its path captured at load time. An in-memory module without a file
  origin raises `OSError`. Returned host buffers are decoded using the async
  OS-string ABI and released after each call.

These hooks must be present in the toolchain/runtime used to build and run the
program. Older versions without them fail at link or module instantiation time,
before the API can raise `OSError`. JS and Wasm-GC are not supported.

Symlink spelling and behavior after renaming or deleting the executable follow
the runtime. Neither API guarantees that the returned path still exists, and
decoding arbitrary OS filenames may be lossy.

Run the package tests with `moon test env --target native` and
`moon test env --target wasm`. Setting `MOONBIT_ASYNC_CHECK_FD_LEAK=1` enables
moonrun's host resource leak checks. Relocation probes can set
`OPENSEEK_TEST_CURRENT_EXE` and `OPENSEEK_TEST_CURRENT_EXE_DIR` to assert exact
paths when launching a copied test artifact from another directory.
