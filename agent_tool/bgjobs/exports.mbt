// Deliberate exports with no production consumer (see shrink_package.md):
// symbols here are part of the package's intended surface even though only
// tests or future callers use them today.

///|
/// Snapshot every job, newest last. Exported for cross-package tests: the
/// mbtx and job_output background-job tests observe runtime state through
/// this seam.
pub fn BgJobRuntime::list(self : BgJobRuntime) -> Array[BgJobSnapshot] {
  [
    for _, job in self.jobs => job.to_snapshot()
  ]
}
