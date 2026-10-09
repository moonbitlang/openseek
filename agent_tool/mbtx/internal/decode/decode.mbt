///|
/// Inline code, an existing script, or code to save before running.
pub enum Program {
  Source(String)
  File(String)
  Save(String, String)
} derive(Debug)

///|
/// Decoded program and execution options. `None` cwd means workspace root.
pub struct MbtxInput {
  program : Program
  /// Script arguments, excluding the executable name. Defaults to empty.
  args : Array[String]
  /// Presentation metadata, inherited by a background job.
  description : String?
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
  /// Enable run-scoped programmatic access to explicitly registered leaf tools.
  ptc : Bool?
} derive(Debug)

///|
#deprecated("the derived Debug impl is the API")
#doc(hidden)
pub extend Program with Debug::{to_repr}

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
/// Decode `mbtx` tool-call arguments. At least one of `source` and `filename`
/// is required; both means save and run a workspace script. `source` is a string
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
    Object(fields) => {
      let program = match (fields.get("source"), fields.get("filename")) {
        (Some(String(source)), Some(String(filename))) => {
          guard !filename.is_blank() else {
            fail(
              "arguments.filename to be a nonblank workspace path when saving source",
            )
          }
          guard !filename.has_prefix("@") else {
            fail(
              "a workspace filename when source is supplied. Namespaced scripts are read-only: call {\"filename\":\"@builtin/check.mbtx\"} without source, or save your custom source as {\"source\":\"...\",\"filename\":\"check.mbtx\"}",
            )
          }
          Save(source, filename)
        }
        (Some(_), Some(_)) =>
          fail(
            "source and filename to both be strings for save-and-run. Omit unused fields entirely instead of sending null",
          )
        (Some(String(source)), None) => Source(source)
        (None, Some(String(filename))) => {
          guard !filename.is_blank() else {
            fail(
              "arguments.filename to be a nonblank path to an existing script, for example {\"filename\":\"./check.mbtx\"}. Omit source entirely",
            )
          }
          File(filename)
        }
        (None, None) =>
          fail(
            "source or filename. Use {\"source\":\"fn main { println(42) }\"} for inline code, {\"filename\":\"./check.mbtx\"} for an existing script, or both strings to save and run. Omit unused fields entirely; do not send null",
          )
        (Some(_), None) =>
          fail(
            "arguments.source to be a string containing a complete .mbtx program. To run a saved script, omit source entirely and use {\"filename\":\"./check.mbtx\"}; do not send source: null",
          )
        (None, Some(_)) =>
          fail(
            "arguments.filename to be a string naming an existing script, for example {\"filename\":\"./check.mbtx\"}. For inline code, omit filename entirely and pass source; do not send filename: null",
          )
      }
      let args : Array[String] = match fields.get("args") {
        None => []
        Some(Array(values)) =>
          values.map(value => {
            guard value is String(text) else {
              fail("arguments.args to be an array of strings")
            }
            text
          })
        Some(_) => fail("arguments.args to be an array of strings")
      }
      let description = match arguments {
        { "description": String(text), .. } => Some(text)
        { "description": Null, .. } => None
        { "description": _, .. } => fail("arguments.description to be a string")
        _ => None
      }
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
        { "warning": "on", .. } => true
        { "warning": "off", .. } => false
        { "warning": Null, .. } => false
        { "warning": _, .. } =>
          fail("arguments.warning to be \"on\" or \"off\"")
        _ => false
      }
      let escalated = match arguments {
        { "escalated": true, .. } => true
        { "escalated": false, .. } | { "escalated": Null, .. } => false
        { "escalated": _, .. } => fail("arguments.escalated to be a boolean")
        _ => false
      }
      let subrun = match arguments {
        { "subrun": true, .. } => true
        { "subrun": false, .. } | { "subrun": Null, .. } => false
        { "subrun": _, .. } => fail("arguments.subrun to be a boolean")
        _ => false
      }
      let ptc = match fields.get("ptc") {
        Some(True) => Some(true)
        Some(False) => Some(false)
        // Like every other optional argument here, an explicit null is unset.
        None | Some(Null) => None
        _ => fail("arguments.ptc to be a boolean")
      }
      {
        program,
        args,
        description,
        target,
        cwd,
        warning,
        escalated,
        subrun,
        ptc,
      }
    }
    _ => fail("object arguments")
  }
}

///|
/// Re-export the derived `Debug` representation as a trait extension so the
/// method stays callable. Deliberately not promoted into a method on
/// `MbtxInput` — the derived `Debug` impl is the real API.
#deprecated("the derived Debug impl is the API; use @debug.repr or the trait directly")
#doc(hidden)
pub extend MbtxInput with Debug::{to_repr}
