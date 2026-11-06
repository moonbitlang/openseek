///|
// Resolve inside the owning search/repair task so preparation is cancellable.
struct SemanticProvider {
  engine : String
  runtime_dir : @pathx.Path?
  source : @moonbit.ToolchainSource
}

///|
pub fn SemanticProvider::SemanticProvider(
  engine~ : String,
  runtime_dir~ : @pathx.Path?,
  source~ : @moonbit.ToolchainSource,
) -> SemanticProvider {
  { engine, runtime_dir, source, }
}

///|
pub async fn SemanticProvider::resolve(
  self : SemanticProvider,
  env~ : Map[String, String] = @env.get_env_vars(),
) -> ResolvedSemanticProvider {
  let toolchain = @moonbit.resolve_toolchain(
    self.engine,
    runtime_dir?=self.runtime_dir,
    source=self.source,
  )
  toolchain.apply_to_env(env)
  let name = if toolchain.moon.to_string().has_suffix(".exe") {
    "moonx.exe"
  } else {
    "moonx"
  }
  { command: toolchain.bin_dir.join(name).to_string(), environment: env, }
}

///|
pub struct ResolvedSemanticProvider {
  command : String
  environment : Map[String, String]
}

///|
/// moongrep publishes no release binaries, so it runs as `moonx <coordinate> --`
/// through the selected toolchain. Pinning the version keeps search and
/// Pattern Repair deterministic instead of running whatever the local registry
/// index knows as "latest".
pub const MoongrepPackageCoordinate : String = "moonbit-community/moongrep@0.3.5"

///|
pub fn moongrep_args(args : Array[String]) -> Array[String] {
  [MoongrepPackageCoordinate, "--", ..args]
}
