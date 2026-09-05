///|
/// Decoded arguments of the `mbtx` tool: a self-contained MoonBit
/// program (`.mbtx` single-file script) to compile and run, the backend
/// `target` to run it on, and an optional `cwd` (the working directory the
/// program runs in; `None` means the workspace root).
pub struct MbtxInput {
  source : String
  target : String
  cwd : String?
  /// Whether compiler warnings appear in the run output — decoded from the
  /// `"on"`/`"off"` tool argument, defaulting to `"off"` (suppressed).
  warning : Bool
  /// Whether the snippet asked to run with no sandbox policy — no spawn
  /// allowlist and no write-root bound. Decoded here whatever the tool was
  /// built with: a build that offers no approval channel does not advertise
  /// the field, but a model that sends it anyway must be told what happened,
  /// not silently run confined while believing otherwise.
  escalated : Bool
  /// Whether the snippet declares that it will DELEGATE — run a
  /// `moonbitlang/workflow` workflow whose children must be visible. Only
  /// then does the tool reserve child ordinals and a run directory and hand
  /// the snippet a `WORKFLOW_HOST`; every other snippet gets none, so the
  /// announcement of a workflow means one was asked for. Decoded whatever the
  /// tool was built with, for the same reason as `escalated`: a model that
  /// asks on a session that cannot host must be told, not quietly run
  /// without its children.
  subrun : Bool
} derive(Debug)

///|
/// The moon backends `--target` accepts.
fn valid_target(target : String) -> Bool {
  // `native` is deliberately absent: moonrun's policy — the only confinement
  // that holds off macOS — applies to the wasm backend alone, and
  // `--wasm-policy` is silently ignored elsewhere. Letting a snippet name
  // `native` would hand it a one-argument way out of the sandbox. The
  // remaining alternatives cannot spawn or touch the filesystem at all.
  target is ("wasm" | "wasm-gc" | "js" | "llvm")
}

///|
/// Decode `mbtx` tool-call arguments. `source` is a required string
/// holding a full `.mbtx` program (an optional leading `import { … }` block,
/// then the program including its own `main`). `target` is an optional backend
/// name defaulting to `wasm`, which is the backend moonrun's policy sandbox
/// applies to — a snippet may not simply ask for an unsandboxed one, so the
/// compute-only backends are the only alternatives offered. `cwd` is an
/// optional working directory for the program (defaults to the workspace
/// root). Failures name the offending field.
pub fn decode(arguments : Json) -> MbtxInput raise {
  // The local dispatcher does not enforce JSON Schema. Reject the removed
  // field explicitly so a stale caller cannot silently get the runtime-less
  // 300s foreground behavior while believing it requested a job.
  if arguments is { "run_in_background": _, .. } {
    fail(
      "arguments without run_in_background; that field was removed and background handoff is automatic when a job runtime is available",
    )
  }
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
      let escalated = match arguments {
        { "escalated": True, .. } => true
        { "escalated": False, .. } | { "escalated": Null, .. } => false
        { "escalated": _, .. } => fail("arguments.escalated to be a boolean")
        _ => false
      }
      let subrun = match arguments {
        { "subrun": True, .. } => true
        { "subrun": False, .. } | { "subrun": Null, .. } => false
        { "subrun": _, .. } => fail("arguments.subrun to be a boolean")
        _ => false
      }
      { source, target, cwd, warning, escalated, subrun, }
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
test "decode rejects the removed background flag with migration guidance" {
  let message = try {
    decode({ "source": "x", "run_in_background": true }) |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(message.contains("was removed"))
  assert_true(message.contains("automatic"))
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
    decode(Json("x")) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
/// Re-export the derived `Debug` representation as a trait extension so the
/// method stays callable. Deliberately not promoted into a method on
/// `MbtxInput` — the derived `Debug` impl is the real API.
#deprecated("the derived Debug impl is the API; use @debug.repr or the trait directly")
#doc(hidden)
pub extend MbtxInput with Debug::{to_repr}
