///|
/// `launch_argv` decides how an assembled child argv reaches the OS. The
/// wasm rewrite is what keeps sub-runs alive under `moonx`, and it has to
/// leave every non-wasm child — real binaries and the scripted test children
/// alike — exactly as it found it.

///|
test "a wasm engine is launched through its runtime" {
  let (command, args) = launch_argv("/cache/openseek.wasm", [
    "subrun", "explore", "--model", "deepseek-v4-flash",
  ])
  assert_eq(command, "moonrun")
  // The module comes first and `--` fences it off, or moonrun would read the
  // engine's own flags as its own.
  assert_eq(args, [
    "/cache/openseek.wasm", "--", "subrun", "explore", "--model", "deepseek-v4-flash",
  ])
}

///|
test "a childless argv still gets the fence" {
  let (command, args) = launch_argv("/cache/openseek.wasm", [])
  assert_eq(command, "moonrun")
  assert_eq(args, ["/cache/openseek.wasm", "--"])
}

///|
test "a native engine is spawned directly" {
  let argv = ["subrun", "review"]
  let (command, args) = launch_argv("/usr/local/bin/openseek", argv)
  assert_eq(command, "/usr/local/bin/openseek")
  assert_eq(args, argv)
}

///|
/// The scripted children the runner tests use, and a PATH-resolved bare name,
/// must be untouched: the suffix is the only trigger.
test "scripted and PATH-resolved children are untouched" {
  let (sh, sh_args) = launch_argv("sh", ["-c", "echo hi"])
  assert_eq(sh, "sh")
  assert_eq(sh_args, ["-c", "echo hi"])
  let (bare, bare_args) = launch_argv("openseek", ["subrun", "explore"])
  assert_eq(bare, "openseek")
  assert_eq(bare_args, ["subrun", "explore"])
}

///|
/// `.wasm` has to be the SUFFIX, not merely present: a directory named for
/// the backend, or a binary whose name embeds it, is still a real executable.
test "only a trailing .wasm triggers the rewrite" {
  let (in_dir, _) = launch_argv("/build/wasm/openseek", [])
  assert_eq(in_dir, "/build/wasm/openseek")
  let (named, _) = launch_argv("/build/openseek.wasm.bak", [])
  assert_eq(named, "/build/openseek.wasm.bak")
}
