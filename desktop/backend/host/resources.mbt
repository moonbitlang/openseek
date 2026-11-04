///|
/// Tool paths chosen by the embedding host. None means unavailable; shared
/// operations never reinterpret an absent bundled tool as a PATH fallback.
pub struct HostResources {
  moonbit : @moonbit.ToolchainSource
  viz : VizAssets?
  bin_dir : String?
  ripgrep : String?
  moongrep : String?
}

///|
/// Explicit environment-based policy for unbundled tools and focused tests.
pub fn HostResources::from_path() -> HostResources {
  {
    moonbit: External,
    viz: None,
    bin_dir: None,
    ripgrep: Some("rg"),
    moongrep: Some("moonx"),
  }
}

///|
/// The visualizer shell and compiled bundle used for a standalone export.
pub struct VizAssets {
  shell : String
  bundle : String
}
