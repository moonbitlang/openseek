# agent_worker

The `worker` subrun kind: a write-capable subagent confined to one git
worktree, completing one assigned slice of work. The CHILD half lives here —
`run_child` decodes the controller-provided geometry (worktree root, denied
roots, private git admin dir, allowed paths, base commit), assembles the
confined toolset (WriteScope'd file tools sharing one FileStateMap, the
worker-sandboxed shell, worker-rooted `mbtx`, and the `submit_result`
capture tool), and runs the slice to a bounded `WorkerReport`. The parent
side — worktree provisioning, launch, scope validation, commit, and
integration — is the worker controller's job — `agent_workflow`'s worker runner
(design history: `docs/plans/subtask-worker-subagents.md`).

The report is advisory by design: the controller validates the worker's
actual changed paths and diffs at the git level; `status`/`summary`/
`verification` tell the delegating agent what the worker believes happened
and how it checked.
