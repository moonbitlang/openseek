///|
async test "background rendering changes take effect after loading preferences again" {
  guard @async.platform is MacOS else { return }
  let dir = @fs.tmpdir(prefix="seekmoon-background-rendering-")
  defer @fs.rmdir(dir)
  let path = dir + "/background-rendering.json"
  defer (@fs.remove(path) catch { _ => () })
  let first = load_background_rendering(Some(dir))
  let original = first.settings()
  assert_true(original.supported)
  assert_false(original.enabled)
  assert_false(original.launch_enabled)
  assert_true(original.error is None)

  let saved = first.save(true)
  assert_true(saved.enabled)
  assert_false(saved.launch_enabled)
  let restarted = load_background_rendering(Some(dir))
  assert_true(restarted.settings().launch_enabled)
  let saved = restarted.save(false)
  assert_false(saved.enabled)
  assert_true(saved.launch_enabled)
  assert_false(load_background_rendering(Some(dir)).settings().launch_enabled)

  @fs.write_file(path, "{invalid", create_mode=CreateOrTruncate)
  let invalid = load_background_rendering(Some(dir)).settings()
  assert_false(invalid.enabled)
  assert_false(invalid.launch_enabled)
  assert_true(invalid.error is Some(_))
}
