///|
async test "desktop resource selection preserves missing tools and lazy export validation" {
  let root = @pathx.Path(@fs.tmpdir(prefix="host-resource-policy-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let selected = resources({ dir: root, packaged: true, })
  assert_true(selected.moonbit is DesktopBundle)
  assert_true(selected.ripgrep is None)
  assert_true(selected.bin_dir is None)
  // The registry provider remains an explicit desktop policy when no standalone
  // moongrep was packaged. An embedder can instead disable it with None.
  assert_eq(selected.moongrep, Some("moonx"))
  guard selected.viz is Some(assets) else {
    fail("missing selected export paths")
  }
  try assets.read() catch {
    _ => ()
  } noraise {
    _ => fail("missing export assets were accepted")
  }
}
