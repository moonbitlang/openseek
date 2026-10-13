///|
#cfg(not(platform="windows"))
async test "bundle replacement checks the containing directory" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-update-replacement-")
    // async 0.22: group defers are `nocancel`; shield the cancellable
    // chmod (rmdir is already non-cancellable in this version).
    group.add_defer(() => {
      @async.protect_from_cancel(() => {
        @fs.chmod(root, 0o700)
        @fs.rmdir(root, recursive=true)
      })
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
      @async.protect_from_cancel(() => {
        @fs.chmod(root, 0o700)
        @fs.rmdir(root, recursive=true)
      })
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

///|
/// Host processes of one user share the work directory, each running from
/// its own bundle: the installed application beside a development build. A
/// marker belongs to the bundle it names.
async test "a relaunch marker is taken only by the bundle it names" {
  let work = @fs.tmpdir(prefix="openseek-update-marker-")
  defer @fs.rmdir(work, recursive=true)
  // Bundle paths under the fixture: cleanup removes `<bundle>.old`, and a
  // test must not reach for one beside a real installation.
  let installed = "\{work}/installed/SeekMoon.app"
  let development = "\{work}/checkout/SeekMoonDev.app"
  write_relaunch_marker(work_dir=work, bundle_path=installed)
  // The development build exits first, and starts again: neither its exit
  // nor its launch cleanup touches the installed application's marker.
  assert_false(take_relaunch_marker(work_dir=work, bundle_path=development))
  cleanup_leftovers(work_dir=work, bundle_path=development)
  assert_true(take_relaunch_marker(work_dir=work, bundle_path=installed))
  // Taken once: a second exit of the same bundle finds nothing.
  assert_false(take_relaunch_marker(work_dir=work, bundle_path=installed))
}

///|
async test "launch cleanup removes this bundle's own stale marker" {
  let work = @fs.tmpdir(prefix="openseek-update-stale-marker-")
  defer @fs.rmdir(work, recursive=true)
  let installed = "\{work}/installed/SeekMoon.app"
  write_relaunch_marker(work_dir=work, bundle_path=installed)
  cleanup_leftovers(work_dir=work, bundle_path=installed)
  assert_false(take_relaunch_marker(work_dir=work, bundle_path=installed))
}
