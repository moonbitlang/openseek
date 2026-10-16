///|
/// Tool paths chosen by the embedding host. None means unavailable; shared
/// operations never reinterpret an absent bundled tool as a PATH fallback.
pub(all) struct HostResources {
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
const MoongrepPackageCoordinate : String = "moonbit-community/moongrep@0.3.5"

///|
/// The visualizer shell and compiled bundle used for a standalone export.
pub(all) struct VizAssets {
  shell : String
  bundle : String
}

///|
/// Read the visualizer shell and bundle selected by `viz_assets`.
pub async fn VizAssets::read(self : VizAssets) -> (String, String) {
  let shell = @fs.read_file(self.shell).text() catch {
    error =>
      raise HostError::HostError(
        "could not read session visualizer shell: \{error}",
      )
  }
  let bundle = @fs.read_file(self.bundle).text() catch {
    error =>
      raise HostError::HostError(
        "could not read session visualizer bundle: \{error}",
      )
  }
  (shell, bundle)
}
