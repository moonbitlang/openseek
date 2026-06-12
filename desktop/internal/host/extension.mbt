// The package's public face: the lepus extension spec that exposes the host
// to the webview, and the error type its op boundary translates.

///|
/// The lepus extension id; the app manifest must enable it under this name.
pub const ExtensionId = "openseek-desktop"

///|
const ExtensionNamespace = "openseek"

///|
/// A host-side failure with a user-facing message. Ops raise it; the IPC
/// boundary (`to_op_result`) unwraps the message into the `Err` the webview
/// displays.
priv suberror HostError {
  HostError(String)
}

///|
/// Adapt a raising op body to the `Result` the lepus IPC boundary expects: a
/// `HostError` unwraps to the message the webview displays; any other error
/// is rendered as-is, and cancellation keeps propagating.
async fn[Reply] to_op_result(body : async () -> Reply) -> Result[Reply, String] {
  Ok(body()) catch {
    error if @async.is_being_cancelled() => raise error
    HostError(message) => Err(message)
    error => Err(error.to_string())
  }
}

///|
/// The `openseek` IPC extension: every command the webview can invoke, bound
/// to a fresh engine manager. `engine` is the engine executable to spawn.
pub fn openseek_extension(engine : String) -> @app.AppCommandExtensionSpec {
  let manager = new_engine_manager()
  @app.AppCommandExtensionSpec::new(
    ExtensionId,
    ExtensionNamespace,
    [
      @app.AppCommandApiDescriptor::new("connect"),
      @app.AppCommandApiDescriptor::new("start"),
      @app.AppCommandApiDescriptor::new("cancel"),
      @app.AppCommandApiDescriptor::new("steer"),
      @app.AppCommandApiDescriptor::new("list_sessions"),
      @app.AppCommandApiDescriptor::new("load_session"),
      @app.AppCommandApiDescriptor::new("skills_catalog"),
      @app.AppCommandApiDescriptor::new("skill_install"),
      @app.AppCommandApiDescriptor::new("skills_installed"),
      @app.AppCommandApiDescriptor::new("skill_uninstall"),
    ],
    fn(context) {
      context.op_async_result("connect", async fn(_payload : Json) {
        to_op_result(async fn() { run_engine_pump(context, manager) })
      })
      context.op_async_result("start", async fn(payload : StartPayload) {
        to_op_result(async fn() { start_run(context, manager, engine, payload) })
      })
      context.op_async("cancel", async fn(payload : CancelPayload) {
        cancel_run(manager, payload)
      })
      context.op_async("steer", async fn(payload : SteerPayload) {
        steer_run(manager, payload)
      })
      context.op_async_result("list_sessions", async fn(_payload : Json) {
        to_op_result(async fn() { list_sessions(engine) })
      })
      context.op_async_result("load_session", async fn(
        payload : LoadSessionPayload,
      ) {
        to_op_result(async fn() { load_session(engine, payload) })
      })
      context.op_async_result("skills_catalog", async fn(_payload : Json) {
        to_op_result(async fn() { skills_catalog_op() })
      })
      context.op_async_result("skill_install", async fn(
        payload : InstallSkillPayload,
      ) {
        to_op_result(async fn() { install_skill_op(payload) })
      })
      context.op_async_result("skills_installed", async fn(_payload : Json) {
        to_op_result(async fn() { installed_skills_op() })
      })
      context.op_async_result("skill_uninstall", async fn(
        payload : UninstallSkillPayload,
      ) {
        to_op_result(async fn() { uninstall_skill_op(payload) })
      })
      Ok(())
    },
  )
}
