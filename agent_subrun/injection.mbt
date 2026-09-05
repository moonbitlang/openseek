///|
/// The host handoff for a snippet run under this durable session: what an
/// `mbtx` snippet is given so the children it delegates to are visible.
///
/// Built HERE, beside `reserve_subrun_ordinals`, because the injection must
/// draw from the session's one child-ordinal allocator — the same counter
/// `run_subrun` mints `explore` children from, with this session's resumed
/// floor. Two independent counters would hand `<parent>-sr-1` to both a
/// snippet's child and an `explore` child, and the second to append would
/// die against the first's stale snapshot. `agent_subrun/host` owns the
/// document; it is a leaf and cannot name the allocator, so the wiring is
/// this function's whole job.
///
/// `exe` must be absolute (the sandbox admits it by exact path);
/// `workspace_root` is where a child RUNS, since an `explore` child reads code
/// by paths relative to its cwd.
pub fn ChildSession::injection(
  self : ChildSession,
  exe~ : String,
  workspace_root~ : String,
  model? : String,
  api_url? : String,
) -> @host.SubrunInjection {
  let first_free = self.first_free
  @host.SubrunInjection(
    exe~,
    session_root=self.root,
    parent=self.parent,
    workspace_root~,
    model?,
    api_url?,
    reserve_ordinals=count => reserve_subrun_ordinals(count, first_free~),
  )
}

///|
test "a session's injection draws from the shared counter" {
  // Ordinals depend on what this process has already reserved, so the test
  // pins the invariants rather than the numbers: consecutive blocks, disjoint,
  // never below the session's floor.
  let session = ChildSession(root="/store", parent="run7", first_free=1)
  let injection = session.injection(exe="/opt/openseek", workspace_root="/ws")
  let first = injection.reserve()
  let second = injection.reserve()
  assert_true(first.base() >= 1)
  assert_eq(second.base(), first.base() + @host.block_size)
  assert_true(first.dir().has_prefix("/store/run7-wf-"))
}
