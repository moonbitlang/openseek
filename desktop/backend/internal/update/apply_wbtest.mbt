///|
#cfg(not(platform="windows"))
async test "bundle replacement checks the containing directory" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-update-replacement-")
    group.add_defer(() => {
      @fs.chmod(root, 0o700)
      @fs.rmdir(root, recursive=true)
    })
    let bundle = "\{root}/SeekMoon.app"
    @fs.mkdir(bundle)
    @debug.assert_eq(bundle_replacement_failure(bundle), None)
    @fs.chmod(root, 0o500)
    @debug.assert_eq(
      bundle_replacement_failure(bundle),
      Some(BundleReplacementFailureMessage),
    )
  }
}

///|
#cfg(not(platform="windows"))
async test "an unavailable destination stops apply before any mutation" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-update-apply-")
    group.add_defer(() => {
      @fs.chmod(root, 0o700)
      @fs.rmdir(root, recursive=true)
    })
    let bundle = "\{root}/SeekMoon.app"
    let staged = "\{root}/Staged.app"
    let aside = aside_path(bundle)
    @fs.mkdir(bundle)
    @fs.mkdir(staged)
    @fs.mkdir(aside)
    @fs.write_file("\{bundle}/version", "current", create_mode=CreateOrTruncate)
    @fs.write_file("\{staged}/version", "staged", create_mode=CreateOrTruncate)
    @fs.write_file("\{aside}/version", "parked", create_mode=CreateOrTruncate)
    @fs.chmod(root, 0o500)
    try apply_staged(staged_app=staged, bundle_path=bundle) catch {
      UpdateError(message) =>
        assert_eq(message, BundleReplacementFailureMessage)
      error => raise error
    } noraise {
      _ => fail("apply unexpectedly accepted an unwritable destination")
    }
    assert_eq(@fs.read_file("\{bundle}/version").text(), "current")
    assert_eq(@fs.read_file("\{staged}/version").text(), "staged")
    assert_eq(@fs.read_file("\{aside}/version").text(), "parked")
  }
}
