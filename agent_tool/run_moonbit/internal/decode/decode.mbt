///|
/// Decoded arguments of the `run_moonbit` tool: a self-contained MoonBit
/// program (`.mbtx` single-file script) to compile and run, the backend
/// `target` to run it on, and an optional `cwd` (the working directory the
/// program runs in; `None` means the workspace root).
pub struct RunMoonbitInput {
  source : String
  target : String
  cwd : String?
  /// Whether compiler warnings appear in the run output — decoded from the
  /// `"on"`/`"off"` tool argument, defaulting to `"off"` (suppressed).
  warning : Bool
  /// Whether to detach the run as a background job instead of waiting for it.
  /// Only meaningful when the tool was built with a job runtime.
  run_in_background : Bool
} derive(Debug)

///|
/// The moon backends `--target` accepts. `native` is the default because the
/// async IO batteries (`@fs`, `@stdio`, `@process`) require it.
fn valid_target(target : String) -> Bool {
  // `native` is deliberately absent: moonrun's policy — the only confinement
  // that holds off macOS — applies to the wasm backend alone, and
  // `--wasm-policy` is silently ignored elsewhere. Letting a snippet name
  // `native` would hand it a one-argument way out of the sandbox. The
  // remaining alternatives cannot spawn or touch the filesystem at all.
  target is ("wasm" | "wasm-gc" | "js" | "llvm")
}

///|
/// Decode `run_moonbit` tool-call arguments. `source` is a required string
/// holding a full `.mbtx` program (an optional leading `import { … }` block,
/// then the program including its own `main`). `target` is an optional backend
/// name defaulting to `wasm`, which is the backend moonrun's policy sandbox
/// applies to — a snippet may not simply ask for an unsandboxed one, so the
/// compute-only backends are the only alternatives offered. `cwd` is an
/// optional working directory for the program (defaults to the workspace
/// root). Failures name the offending field.
pub fn decode(arguments : Json) -> RunMoonbitInput raise {
  match arguments {
    { "source": String(source), .. } => {
      let target = match arguments {
        { "target": String(t), .. } => t
        { "target": Null, .. } => "wasm"
        { "target": _, .. } => fail("arguments.target to be a string")
        _ => "wasm"
      }
      guard valid_target(target) else {
        fail("arguments.target to be one of wasm, wasm-gc, js, llvm")
      }
      let cwd = match arguments {
        { "cwd": String(c), .. } => Some(c)
        { "cwd": Null, .. } => None
        { "cwd": _, .. } => fail("arguments.cwd to be a string")
        _ => None
      }
      let warning = match arguments {
        { "warning": String("on"), .. } => true
        { "warning": String("off"), .. } => false
        { "warning": Null, .. } => false
        { "warning": _, .. } =>
          fail("arguments.warning to be \"on\" or \"off\"")
        _ => false
      }
      let run_in_background = match arguments {
        { "run_in_background": True, .. } => true
        { "run_in_background": False, .. }
        | { "run_in_background": Null, .. } => false
        { "run_in_background": _, .. } =>
          fail("arguments.run_in_background to be a boolean")
        _ => false
      }
      { source, target, cwd, warning, run_in_background }
    }
    Object(_) => fail("arguments.source")
    _ => fail("object arguments")
  }
}

///|
test "decode reads source with the default wasm target" {
  let input = decode({ "source": "fn main { println(1) }" })
  assert_eq(input.source, "fn main { println(1) }")
  assert_eq(input.target, "wasm")
}

///|
/// `native` is the one backend a snippet may not ask for: moonrun's policy —
/// the confinement that holds on every platform — applies to wasm alone, and
/// `--wasm-policy` is silently ignored elsewhere, so naming `native` would be
/// a one-argument way out of the sandbox.
test "decode refuses the unsandboxed native target" {
  let refused = try {
    decode({ "source": "fn main {  }", "target": "native" }) |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_false(refused == "accepted")
  assert_true(refused.contains("wasm"))
}

///|
test "decode accepts an explicit target" {
  let input = decode({ "source": "fn main {  }", "target": "wasm-gc" })
  assert_eq(input.target, "wasm-gc")
}

///|
test "decode defaults cwd to None and reads an explicit cwd" {
  assert_true(decode({ "source": "x" }).cwd is None)
  assert_eq(decode({ "source": "x", "cwd": "sub/dir" }).cwd, Some("sub/dir"))
}

///|
test "decode defaults warning to off and reads on/off" {
  assert_false(decode({ "source": "x" }).warning)
  assert_false(decode({ "source": "x", "warning": "off" }).warning)
  assert_true(decode({ "source": "x", "warning": "on" }).warning)
}

///|
test "decode rejects an unknown warning value" {
  let failed = try {
    decode({ "source": "x", "warning": "loud" }) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "decode rejects a non-string cwd" {
  let failed = try {
    decode({ "source": "x", "cwd": 3 }) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "decode rejects an unknown target" {
  let failed = try {
    decode({ "source": "x", "target": "banana" }) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "decode rejects a missing source" {
  let failed = try {
    decode({ "code": "x" }) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "decode rejects non-object arguments" {
  let failed = try {
    decode(Json::string("x")) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
pub extend RunMoonbitInput with Debug::{to_repr}
