///|
/// The gate is advisory: when its reviewer's id cannot be recorded, nothing
/// is launched and the met claim is reported as unaudited — the same shape
/// as every other way the audit can fail to happen.
async test "a reviewer whose id cannot be recorded degrades to a notice" {
  let dir = @fs.tmpdir(prefix="openseek-gate-")
  defer @fs.rmdir(dir, recursive=true)
  let children = @agent_subrun.ChildSession(
    root="\{dir}/store",
    parent="p",
    ledger="\{dir}/subagents.jsonl",
  )
  defer children.close()
  // The ledger's path is taken by a directory: the allocation cannot be
  // written.
  @fs.mkdir("\{dir}/subagents.jsonl", recursive=true)
  let gate = build_goal_met_gate(
    // Never run: the launch is refused before anything is spawned.
    self_exe="\{dir}/no-such-engine",
    model=Deepseek(V4Pro),
    api_url=None,
    workspace_root=dir,
    child_session=children,
  )
  guard gate("the tests pass", None) is Some(notice) else {
    fail("the gate always answers a met claim")
  }
  assert_true(notice.has_prefix("[review] unavailable ("))
  assert_true(notice.has_suffix("treat the met claim as unaudited."))
  assert_false(@fs.exists("\{dir}/store"))
}
