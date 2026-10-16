///|
/// Start an unbundled host with the same per-user runtime as Desktop. When
/// launched inside this checkout, use its matching engine and visualizer.
pub async fn Server::from_environment(
  engine~ : String = "openseek",
  port~ : Int32 = 0,
) -> Server {
  let executable = @env.args().get(0).unwrap_or("seekmoon-tui")
  let runtime_dir = @backend_host.prepared_runtime_dir(executable)
  let mut resources = @backend_host.HostResources::from_path()
  let mut selected_engine = engine
  if @env.current_dir() is Some(cwd) {
    let mut directory = @pathx.Path(cwd)
    for ;; {
      if @fs.exists(directory.join("desktop/moon.mod").to_string()) &&
        @fs.exists(directory.join("web/index.html").to_string()) {
        resources = {
          ..resources,
          viz: Some({
            shell: directory.join("web/index.html").to_string(),
            bundle: directory
            .join(
              "_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js",
            )
            .to_string(),
          }),
        }
        if engine == "openseek" {
          for name in ["openseek.exe", "openseek"] {
            let candidate = directory
              .join("_build/native/debug/build/moonbitlang/openseek")
              .join(name)
              .to_string()
            if @fs.exists(candidate) {
              selected_engine = candidate
              break
            }
          }
        }
        break
      }
      let parent = directory.dirname()
      if parent == directory {
        break
      }
      directory = parent
    }
  }
  if selected_engine.contains("/") || selected_engine.contains("\\") {
    selected_engine = @pathx.Path(selected_engine).resolve().to_string()
  }
  Server::bind(engine=selected_engine, port~, runtime_dir?, resources~)
}
