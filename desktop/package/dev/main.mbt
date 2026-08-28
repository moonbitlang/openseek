///|
const ProtonRuntimeRootEnv : String = "PROTON_RUNTIME_ROOT"

///|
const ProtonHelperPathEnv : String = "PROTON_HELPER_PATH"

///|
/// The unbundled launcher replaces `proton dev`, so it must preserve Proton's
/// development-mode contract for frontend diagnostics and development config.
const ProtonModeEnv : String = "PROTON_MODE"

///|
const ProtonResourceDirEnv : String = "PROTON_RESOURCE_DIR"

///|
const ProtonProjectConfigEnv : String = "PROTON_PROJECT_CONFIG"

///|
/// Everything needed to derive a development launch belongs to the detected
/// desktop workspace. The command therefore takes no path arguments.
priv struct Development {
  workspace : @packaging.Workspace
}

///|
/// Compile the MoonBit frontend to its normal `_build` artifact and prepare
/// only the raw third-party files a browser cannot obtain from Moon's graph.
/// The checked-in development HTML references every file in place.
async fn Development::prepare_frontend(self : Development) -> Unit {
  @packaging.build_frontend(self.workspace, release=false)
  @packaging.build_viz_frontend(self.workspace, release=false)
  let mermaid_entry = (self.workspace.mermaid_assets() : @path.Path)
    .join("mermaid.esm.min.mjs")
    .to_string()
  if !@asyncfs.exists(mermaid_entry) {
    @packaging.build_mermaid_assets(self.workspace)
  }
  @xterm_assets.stage_development(self.workspace)
}

///|
/// Prepare the CEF runtime this checkout's Proton dependency calls for.
async fn Development::prepare_runtime(self : Development) -> String {
  @packaging.ensure_cef_runtime(self.workspace)
  let runtime = @packaging.proton_runtime_root().0
  let normalized = (runtime : @path.Path).normalize()
  let helper = @packaging.proton_helper_path()
  guard @asyncfs.exists(helper) else {
    raise @packaging.PackageError("Proton CEF helper not found: \{helper}")
  }
  normalized.to_string()
}

///|
/// Build the checkout-local engine and the unbundled native host. Moon owns
/// both outputs and skips unchanged work on subsequent invocations.
async fn Development::build_native(self : Development) -> Unit {
  @packaging.build_engine(self.workspace, release=false)
  @packaging.build_native_host(self.workspace, release=false)
}

///|
/// Launch the bare host. It derives its checkout HTML, engine, and isolated
/// state directory from the matching Moon build layout, so the launcher only
/// supplies Proton's native runtime environment.
async fn Development::run(self : Development, runtime_root : String) -> Unit {
  let host = self.workspace.native_binary(release=false)
  let engine = self.workspace.engine_binary(release=false)
  let frontend = self.workspace.repo_at("desktop-dev.html")
  guard @asyncfs.exists(host) else {
    raise @packaging.PackageError("development host not found: \{host}")
  }
  guard @asyncfs.exists(engine) else {
    raise @packaging.PackageError("development engine not found: \{engine}")
  }
  guard @asyncfs.exists(frontend) else {
    raise @packaging.PackageError("development HTML not found: \{frontend}")
  }
  let runtime_path : @path.Path = runtime_root
  let bin_dir = runtime_path.join("bin").to_string()
  let lib_dir = runtime_path.join("lib").to_string()
  let helper = @packaging.proton_helper_path()
  let env = @sys.get_env_vars()
  env[ProtonModeEnv] = "dev"
  env[ProtonRuntimeRootEnv] = runtime_root
  env[ProtonHelperPathEnv] = helper
  env[ProtonResourceDirEnv] = self.workspace.dir()
  env[ProtonProjectConfigEnv] = self.workspace.at("proton.project.json")
  @envx.prepend_path_entry(env, bin_dir) |> ignore
  if !(@platform.win32 || @platform.win64) {
    env["LD_LIBRARY_PATH"] = @envx.prepend_to_path_env(
      lib_dir,
      Some(@envx.prepend_to_path_env(bin_dir, @envx.get("LD_LIBRARY_PATH"))),
    )
    env["DYLD_LIBRARY_PATH"] = @envx.prepend_to_path_env(
      lib_dir,
      Some(@envx.prepend_to_path_env(bin_dir, @envx.get("DYLD_LIBRARY_PATH"))),
    )
    if @platform.linux &&
      @asyncfs.exists((bin_dir : @path.Path).join("libcef.so").to_string()) {
      env["LD_PRELOAD"] = @envx.prepend_to_path_env(
        "libcef.so",
        @envx.get("LD_PRELOAD"),
      )
    }
  }
  println("running unbundled SeekMoon: \{host}")
  let code = @process.run(
    host,
    [],
    inherit_env=false,
    extra_env=env,
    cwd=self.workspace.repo().view(),
    cancel_handler=@process.graceful_cancel(timeout=1000),
  )
  if code != 0 {
    raise @packaging.PackageError("development host exited with code \{code}")
  }
}

///|
/// Build and run the unbundled desktop from paths detected from the current
/// monorepo checkout.
async fn main {
  let development : Development = { workspace: @packaging.locate_workspace(), }
  development.prepare_frontend()
  let runtime_root = development.prepare_runtime()
  development.build_native()
  development.run(runtime_root)
}
