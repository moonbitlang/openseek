///|
/// Create a child's scratch lab, realpath'd so the path the child is told,
/// the read-only guard, and the sandbox profile all name the SAME
/// kernel-canonical directory (macOS `/tmp` → `/private/tmp`) — otherwise
/// the sandbox's allow-subpath would never match the writes it means to
/// permit.
pub async fn new_scratch_lab(prefix : String) -> String {
  let dir = @fs.tmpdir(prefix~)
  @fs.realpath(dir) catch {
    _ => dir
  }
}

///|
/// Remove a child's scratch lab after it finishes: `moon check` inside a
/// lab leaves a `_build` tree, so a long run's labs would otherwise
/// accumulate until the OS cleans temp. Best-effort — a failed cleanup is
/// not worth failing the sub-run over.
///
/// Shielded from cancellation: this runs from `defer` on the cancelled path
/// too, where `@fs.rmdir`'s opening `open` would otherwise raise before the
/// directory is touched and the lab would outlive the run.
pub async fn remove_scratch_lab(dir : String) -> Unit {
  @async.protect_from_cancel(() => {
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  })
}
