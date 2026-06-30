///|
async fn main {
  // Proton runs everything in one process; the executable path locates the
  // bundled frontend assets and the engine binary that ship alongside it.
  let executable = match @env.args().get(0) {
    Some(command) => command
    None => abort("current executable command is unavailable")
  }
  let log = launch_logger()
  log.info() <? { "message": "start" }
  let frontend_entry = @extension.frontend_entry_path(executable)
  let engine = @engine.engine_command(executable)
  log.info() <? { "message": "host process start" }
  log.info() <? { "message": "frontend entry", "path": frontend_entry }
  let frontend_asset_dir = @extension.frontend_asset_dir(frontend_entry)
  log.info() <? { "message": "frontend asset dir", "path": frontend_asset_dir }
  log.info() <? { "message": "engine", "path": engine }
  let runtime_dir = @extension.prepared_runtime_dir()
  // Proton exposes the `__MoonBit__` bridge — both the ops and the extension
  // event channel the frontend listens on — only to the `proton://app/` origin
  // its `html()` entry serves from. A `file://` page gets no bridge bootstrap,
  // its events are dropped (the dispatcher requires a `proton:` origin), and in
  // a signed bundle it does not even paint. So hand the frontend document to
  // proton directly and let the same `proton://app/` origin serve sibling
  // static assets such as frontend.js and viewer.css from the bundled assets
  // directory.
  let document = @extension.frontend_document(frontend_entry)
  let app = @proton.html("OpenSeek Desktop", document, width=1120, height=760)
    .asset_dir(frontend_asset_dir)
    .debug_level(1)
    .extension(
      @proton_extension.from_command_spec(
        @extension.openseek_extension(engine, runtime_dir?),
      ),
    )
  match app.run() {
    Ok(_) => log.info() <? { "message": "host process exit ok" }
    Err(error) => {
      log.error() <? { "message": "host process error", "error": error }
      abort(error)
    }
  }
}
