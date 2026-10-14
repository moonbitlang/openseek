///|
// Resolve inside the owning search/repair task so preparation is cancellable.
priv enum SemanticProvider {
  Standalone(String)
  Moonx(
    engine~ : String,
    runtime_dir~ : @pathx.Path?,
    source~ : @moonbit.ToolchainSource
  )
}

///|
fn HostState::semantic_provider(self : HostState) -> SemanticProvider? {
  self.resources.moongrep.map(command => {
    if semantic_provider_prefix_args(command).is_empty() {
      Standalone(command)
    } else {
      Moonx(
        engine=self.engine,
        runtime_dir=self.runtime_dir,
        source=self.resources.moonbit,
      )
    }
  })
}

///|
async fn SemanticProvider::resolve(
  self : SemanticProvider,
  env~ : Map[String, String] = @sys.get_env_vars(),
) -> ResolvedSemanticProvider {
  match self {
    Standalone(command) => { command, environment: env, }
    Moonx(engine~, runtime_dir~, source~) => {
      let toolchain = @moonbit.resolve_toolchain(engine, runtime_dir?, source~)
      toolchain.apply_to_env(env)
      let name = if toolchain.moon.to_string().has_suffix(".exe") {
        "moonx.exe"
      } else {
        "moonx"
      }
      { command: toolchain.bin_dir.join(name).to_string(), environment: env, }
    }
  }
}

///|
priv struct ResolvedSemanticProvider {
  command : String
  environment : Map[String, String]
}

///|
fn semantic_provider_prefix_args(command : String) -> Array[String] {
  if command == "moonx" ||
    command.has_suffix("/moonx") ||
    command.has_suffix("\\moonx") ||
    command == "moonx.exe" ||
    command.has_suffix("/moonx.exe") ||
    command.has_suffix("\\moonx.exe") {
    [MoongrepPackageCoordinate, "--"]
  } else {
    []
  }
}
