///|
async test "desktop resource selection preserves missing tools and lazy export validation" {
  let root = @pathx.Path(@fs.tmpdir(prefix="host-resource-policy-"))
  defer @fs.remove(root.to_string(), recursive=true)
  let resources = desktop_resources({ dir: root, packaged: true, })
  assert_true(resources.moonbit is DesktopBundle)
  assert_eq(resources.skills, Some(root.join("seekmoon/skills").normalize()))
  assert_eq(
    desktop_resources({ dir: root, packaged: false, }).skills,
    Some(root.join("skills").normalize()),
  )
  assert_eq(HostResources::from_path().skills, None)
  let state = new_host_state("unused", resources~)
  try state.viz_assets() catch {
    _ => ()
  } noraise {
    _ => fail("missing export assets were accepted")
  }
}
