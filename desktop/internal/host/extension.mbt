// The package's public face: the lepus extension spec that exposes the host
// to the webview, and the error type its op boundary translates.

///|
/// The lepus extension id; the app manifest must enable it under this name.
pub const ExtensionId = "openseek-desktop"

///|
const ExtensionNamespace = "openseek"

///|
/// A host-side failure with a user-facing message. Ops raise it; the IPC
/// boundary stringifies it into the `Err` the webview displays.
priv suberror HostError {
  HostError(String)
}

///|
impl Show for HostError with fn output(self, logger) {
  match self {
    HostError(message) => logger.write_string(message)
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
    context => {
      context.op_async("connect", (_ : Json) => {
        run_engine_pump(context, manager)
      })
      context.op_async("start", (payload : StartPayload) => {
        start_run(context, manager, engine, payload)
      })
      context.op_async("cancel", async fn(payload : CancelPayload) {
        cancel_run(manager, payload)
      })
      context.op_async("steer", async fn(payload : SteerPayload) {
        steer_run(manager, payload)
      })
      context.op_async("list_sessions", async fn(_ : Json) {
        list_sessions(engine)
      })
      context.op_async("load_session", async fn(payload : LoadSessionPayload) {
        load_session(engine, payload)
      })
      context.op_async("skills_catalog", async fn(_ : Json) {
        skills_catalog_op()
      })
      context.op_async("skill_install", async fn(
        payload : InstallSkillPayload,
      ) {
        install_skill_op(payload)
      })
      context.op_async("skills_installed", async fn(_ : Json) {
        installed_skills_op()
      })
      context.op_async("skill_uninstall", async fn(
        payload : UninstallSkillPayload,
      ) {
        uninstall_skill_op(payload)
      })
      Ok(())
    },
  )
}
