// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Exercise every agent tool once through the real registry — decode,
/// dispatch, execute, and check each tool's happy path plus a
/// representative failure — and return the per-case report. This is the
/// offline tool smoke test: no model involved, so a failure localizes to
/// the tool layer itself. The package's own test driver is the intended
/// caller — this export IS the harness entry point.
pub async fn run_harness() -> @report.Report {
  run_harness_with_runtime(AgentRuntime())
}
