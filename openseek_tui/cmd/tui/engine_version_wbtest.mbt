///|
/// The default engine's pinned release must be the one this module compiles
/// against: the UI decodes that release's `serve` events and reads its session
/// files, so bumping the `moon.mod` import without the constant (or the reverse)
/// would pair the UI with an engine speaking a different protocol. The module's
/// own `version` moves in lockstep with it, so `openseek_tui@X` always runs
/// `openseek@X`. Moon runs tests from the module root, where `moon.mod` lives.
async test "EngineModuleVersion matches the moonbitlang/openseek import and the module version" {
  let lines = @fs.read_file("moon.mod")
    .text()
    .split("\n")
    .map(line => line.trim())
    .to_array()
  // The quoted value after `prefix` on every manifest line that starts with it.
  let quoted_after = (prefix : String) => {
    lines
    .iter()
    .filter_map(line => {
      guard line.has_prefix(prefix) else { return None }
      line[prefix.length():].split("\"").next().map(value => value.to_owned())
    })
    .to_array()
  }
  @debug.assert_eq(quoted_after("\"moonbitlang/openseek@"), [
    EngineModuleVersion,
  ])
  @debug.assert_eq(quoted_after("version = \""), [EngineModuleVersion])
}
