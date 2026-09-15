///|
/// Preserve the historical Moon entrypoints while one Node program owns the
/// actual cross-platform build. Arguments are forwarded unchanged; build.mjs
/// is the only layer that parses them.
/// These native-only packages live in the desktop module and do not import
/// the backend; the build program compiles backend and frontend separately.
pub async fn run(command : String) -> Unit {
  let desktop = if @asyncfs.exists("package/build.mjs") {
    "."
  } else if @asyncfs.exists("desktop/package/build.mjs") {
    "desktop"
  } else {
    fail("desktop/package/build.mjs was not found")
  }
  let user_args = match @env.args() {
    [_, .. args] => args
    [] => []
  }
  let code = @process.run(
    "node",
    ["package/build.mjs", command, ..user_args],
    cwd=desktop,
    inherit_env=true,
    cancel_handler=@process.graceful_cancel(timeout=1000),
  )
  if code != 0 {
    fail("\{command} build failed with exit code \{code}")
  }
}
