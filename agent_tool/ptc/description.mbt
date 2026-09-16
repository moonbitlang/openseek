///|
/// Script-facing API and execution constraints, appended only by a host that
/// can actually serve programmatic calls. Sent to the model on every request
/// while PTC is available, so it carries only what a script author needs:
/// activation and mode rules live on the `ptc` argument's own schema text,
/// and hosting, lifetime, and wire bounds live in this package's README.
/// The text is generated from `ptc_description.md`, whose whole-line links
/// to `share/examples/*.mbtx` are expanded into the verified examples.
pub fn description() -> String {
  ptc_description()
}
