///|
/// Script-facing API and execution constraints, appended only by a host that
/// can actually serve programmatic calls.
pub fn description() -> String {
  (
    #|
    #|
    #|## Programmatic tool calls (PTC)
    #|
    #|PTC defaults on for supported wasm runs. Set ptc=false to opt out. Explicitly
    #|import the SDK and async runtime; the host does not rewrite source:
    #|
    #|  import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
    #|
    #|Use ordinary MoonBit async functions, with no await keyword:
    #|
    #|  let result = @tools.call("edit", {
    #|    "path": "note.txt", "start_line": 1,
    #|    "old_string": "before", "new_string": "after",
    #|  })
    #|  if result.is_error { fail(result.content) }
    #|
    #|`@tools.call(name, arguments)` is the whole API. `arguments` is the same
    #|JSON object the direct host tool takes, forwarded unchanged; validation and
    #|defaults stay in the host. edit, multi_edit (edits or edits_file), and
    #|web_search (when registered) are the PTC-enabled tools.
    #|
    #|Results have content : String, is_error : Bool, data : Json?. Tool errors
    #|are results; transport failures raise and MUST NOT automatically retry a
    #|mutation because its outcome may be unknown. Search data is
    #|{sources:[{url,title?,snippet?,published_at?}],truncated:Bool}. Missing
    #|fields are absent, not empty strings. Keep selected URLs when printing
    #|sources so the final answer can cite them.
    #|
    #|Normal background handoff is unchanged: the script can keep calling tools
    #|after receiving a job ID. job_stop revokes its capability and joins active
    #|calls. Explicit ptc=true cannot combine with subrun, escalated, or another
    #|target; omitted ptc stays off in those modes. Up to 64 calls per script,
    #|64 KiB per request, 64K characters per result, four active calls per script,
    #|and 512 KiB retained trace plus framing. Stateful calls serialize; independent
    #|searches can overlap using a MoonBit task group. Batch related edits with
    #|multi_edit to retain its validation and rollback semantics. finish, goal,
    #|plan, job controls, and recursive mbtx calls are unavailable.
    #|
    #|Foreground calls are recorded under the mbtx result. Background calls are
    #|retained with the job and returned as metadata by job_output. Only the
    #|script's printed output returns to model context. Print concise selected
    #|results, handle is_error explicitly, and stop when further steps require
    #|model judgment.
  )
}
