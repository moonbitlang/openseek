///|
/// Preserve the historical Moon entrypoints while one Node program owns the
/// actual cross-platform build. Arguments are forwarded unchanged; build.mjs
/// is the only layer that parses them.
pub async fn run(command : String) -> Unit {
  let backend = if @asyncfs.exists("package/build.mjs") {
    "."
  } else if @asyncfs.exists("desktop/backend/package/build.mjs") {
    "desktop/backend"
  } else {
    fail("desktop/backend/package/build.mjs was not found")
  }
  let user_args = match @env.args() {
    [_, .. args] => args
    [] => []
  }
  let code = @process.run(
    "node",
    ["package/build.mjs", command, ..user_args],
    cwd=backend,
    inherit_env=true,
    cancel_handler=@process.graceful_cancel(timeout=1000),
  )
  if code != 0 {
    fail("\{command} build failed with exit code \{code}")
  }
}
