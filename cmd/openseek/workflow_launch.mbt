///|
/// Resolve the hosted workflow's command before generating its handoff and
/// process rule. The fence keeps engine arguments out of moonrun's options.
fn workflow_launch(exe : String) -> (String, Array[String]) {
  if exe.has_suffix(".wasm") {
    ("moonrun", [exe, "--"])
  } else {
    (exe, [])
  }
}
