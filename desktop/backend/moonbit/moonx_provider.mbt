///|
/// The selected toolchain's moonx and child environment, shared by registry
/// commands. Resolve inside the owning task so preparation is cancellable.
struct MoonxProvider {
  engine : String
  runtime_dir : @pathx.Path?
  source : ToolchainSource
}

///|
pub fn MoonxProvider::MoonxProvider(
  engine~ : String,
  runtime_dir~ : @pathx.Path?,
  source~ : ToolchainSource,
) -> MoonxProvider {
  { engine, runtime_dir, source, }
}

///|
pub async fn MoonxProvider::resolve(
  self : MoonxProvider,
  env~ : Map[String, String] = @sys.get_env_vars(),
) -> ResolvedMoonxProvider {
  let toolchain = resolve_toolchain(
    self.engine,
    runtime_dir?=self.runtime_dir,
    source=self.source,
  )
  toolchain.apply_to_env(env)
  { command: toolchain.moonx().to_string(), environment: env, }
}

///|
pub struct ResolvedMoonxProvider {
  command : String
  environment : Map[String, String]
}
