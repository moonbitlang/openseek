///|
/// The host handoff for a snippet run under this durable session: what an
/// `mbtx` snippet is given so the children it delegates to are visible.
///
/// Built HERE because the injection must draw from the session's one
/// child-ordinal allocator — the ledger `run_subrun` mints its children
/// from. Two independent counters would hand `<parent>-sr-1` to both a
/// snippet's child and a direct sub-run, and the second to append would
/// die against the first's stale snapshot. A block is recorded in the ledger
/// before the snippet is given it, so it stays taken even if this engine
/// dies while the snippet lives on. `agent_subrun/host` owns the
/// document; it is a leaf and cannot name the allocator, so the wiring is
/// this function's whole job.
///
/// `exe` and `launch_prefix` are the host's resolved launch command, shared
/// with its direct sub-runs. `workspace_root` is where a child runs.
/// `criteria` is read when a snippet is reserved, so its review audits the
/// live standing goal.
pub fn ChildSession::injection(
  self : ChildSession,
  exe~ : String,
  launch_prefix? : Array[String] = [],
  workspace_root~ : String,
  model? : String,
  api_url? : String,
  criteria? : () -> @host.AuditCriteria?,
) -> @host.SubrunInjection {
  SubrunInjection(
    exe~,
    launch_prefix~,
    session_root=self.root,
    parent=self.parent,
    workspace_root~,
    model?,
    api_url?,
    criteria?,
    reserve_ordinals=count => self.allocate(count~, owner="workflow"),
  )
}
