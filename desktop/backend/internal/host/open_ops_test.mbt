///|
async test "ensure_codex_config creates the file once and keeps edits" {
  let home = @fs.tmpdir(prefix="openseek-codex-config-")
  let nested = @pathx.Path("\{home}/isolated/codex")
  let created = @host.ensure_codex_config(Some(nested))
  assert_eq(created, "\{home}/isolated/codex/config.toml")
  let seeded = @fs.read_file(created).text()
  assert_true(seeded.has_prefix("# Codex configuration"))
  // A later call returns the same path without touching user edits.
  @fs.write_file(created, "model = \"gpt-5.4\"\n", create_mode=CreateOrTruncate)
  let again = @host.ensure_codex_config(Some(nested))
  assert_eq(again, created)
  assert_eq(@fs.read_file(created).text(), "model = \"gpt-5.4\"\n")
}
