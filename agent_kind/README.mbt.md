# agent_kind

What a sub-run *kind* is made of, with no process in sight. A kind (review,
explore, worker, pattern repair, ...) is one bounded agent turn over a
restricted toolset that ends by submitting a typed value through a
`capture_tool`. `execute_kind` runs that turn in the calling process and
returns the captured value; it never spawns and never learns whether it is
inside an `openseek subrun <kind>` child, the standalone review CLI, or a
unit test against a mock endpoint — those are its three callers. The process
boundary (spawn, wall deadline, cost accounting, terminal classification,
the `{"subrun_report": ...}` stdout line) is `agent_subrun`'s job, and that
package never imports this one.

- `execute_kind`: build the session, run one turn with the kind's toolset,
  return what the submit tool captured (`None` if the model finished without
  submitting).
- `capture_tool`: the submit-style control tool — parse/validate,
  reject-with-retry, capture + `Control(Finish)`, `control=true` so the
  loop's ceiling salvage honors a pending submission.
- `validated`: combine a report type's `parse` result and `validate` pass
  into the `Result[T, Array[String]]` shape `capture_tool` expects, so each
  kind defines its contract once, on its report type.
