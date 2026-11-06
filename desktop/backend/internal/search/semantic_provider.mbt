///|
// Resolve inside the owning search/repair task so preparation is cancellable.
enum SemanticProvider {
  Standalone(String)
  Moonx(
    engine~ : String,
    runtime_dir~ : @pathx.Path?,
    source~ : @moonbit.ToolchainSource
  )
}

///|
pub fn semantic_provider(
  command : String,
  engine~ : String,
  runtime_dir~ : @pathx.Path?,
  source~ : @moonbit.ToolchainSource,
) -> SemanticProvider {
  if semantic_provider_prefix_args(command).is_empty() {
    Standalone(command)
  } else {
    Moonx(engine~, runtime_dir~, source~)
  }
}

///|
pub async fn SemanticProvider::resolve(
  self : SemanticProvider,
  env~ : Map[String, String] = @env.get_env_vars(),
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
pub struct ResolvedSemanticProvider {
  command : String
  environment : Map[String, String]
}

///|
pub fn semantic_provider_prefix_args(command : String) -> Array[String] {
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

///|
/// The pinned mooncakes coordinate used when the host resolves moongrep through
/// `moonx`. Search and Pattern Repair must validate with the same provider.
pub const MoongrepPackageCoordinate : String = "moonbit-community/moongrep@0.3.5"
