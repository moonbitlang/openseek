///|
/// Script-facing API and execution constraints, appended only by a host that
/// can actually serve programmatic calls. Sent to the model on every request
/// while PTC is available, so it carries only what a script author needs:
/// activation and mode rules live on the `ptc` argument's own schema text,
/// and hosting, lifetime, and wire bounds live in this package's README.
pub fn description() -> String {
  (
    #|
    #|
    #|## Programmatic tool calls (PTC)
    #|
    #|Import the SDK and async runtime explicitly; the host does not rewrite
    #|source. Use ordinary MoonBit async functions, with no await keyword:
    #|
    #|  import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
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
    #|web_search (when registered) are the PTC-enabled tools; finish, goal, plan,
    #|job controls, and recursive mbtx calls are unavailable.
    #|
    #|Results have content : String, is_error : Bool, data : Json?. Tool errors
    #|are results; transport failures raise and MUST NOT automatically retry a
    #|mutation because its outcome may be unknown. Search data is
    #|{sources:[{url,title?,snippet?,published_at?}],truncated:Bool}. Missing
    #|fields are absent, not empty strings. Keep selected URLs when printing
    #|sources so the final answer can cite them.
    #|
    #|Up to 64 calls per script, four in flight, 64 KiB per request, and 64K
    #|characters per result; a larger edit batch goes through edits_file.
    #|Stateful calls serialize; independent searches can overlap using a MoonBit
    #|task group. Batch related edits with multi_edit to retain its validation
    #|and rollback semantics.
    #|
    #|Normal background handoff is unchanged: the script can keep calling tools
    #|after receiving a job ID, and job_output returns the nested calls as
    #|metadata. Only the script's printed output returns to model context. Print
    #|concise selected results, handle is_error explicitly, and stop when further
    #|steps require model judgment.
  )
}
