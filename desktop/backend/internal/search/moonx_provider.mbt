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
