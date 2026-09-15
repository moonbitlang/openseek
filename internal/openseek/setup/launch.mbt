///|
/// Resolve a child engine's command before spawning it: the hosted workflow's
/// handoff and process rule, and the review gate's audit child. A wasm module
/// needs moonrun, the host providing this engine's process, filesystem and
/// socket APIs; the fence keeps engine arguments out of moonrun's options.
pub fn workflow_launch(exe : String) -> (String, Array[String]) {
  if exe.has_suffix(".wasm") {
    ("moonrun", [exe, "--"])
  } else {
    (exe, [])
  }
}
