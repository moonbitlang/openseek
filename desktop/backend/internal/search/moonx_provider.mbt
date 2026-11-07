///|
/// The selected toolchain's `moonx`, which runs the pinned search packages
/// (cli/rg for text search, moongrep for semantic search and Pattern Repair).
/// Resolve inside the owning search/repair task so preparation is cancellable.
struct MoonxProvider {
  engine : String
  runtime_dir : @pathx.Path?
  source : @moonbit.ToolchainSource
}

///|
pub fn MoonxProvider::MoonxProvider(
  engine~ : String,
  runtime_dir~ : @pathx.Path?,
  source~ : @moonbit.ToolchainSource,
) -> MoonxProvider {
  { engine, runtime_dir, source, }
}

///|
pub async fn MoonxProvider::resolve(
  self : MoonxProvider,
  env~ : Map[String, String] = @env.get_env_vars(),
) -> ResolvedMoonxProvider {
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
pub struct ResolvedMoonxProvider {
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

///|
/// Text search runs cli/rg, the MoonBit port of ripgrep, through moonx. The
/// pinned version keeps its flags and `--json` output fixed for this host.
const RgPackageCoordinate : String = "cli/rg@0.1.1"

///|
/// `--` keeps moonx from reading rg's leading flags as its own options.
fn rg_args(args : Array[String]) -> Array[String] {
  [RgPackageCoordinate, "--", ..args]
}
