

## Programmatic tool calls (PTC)

Import the SDK and async runtime explicitly; the host does not rewrite
source. Use ordinary MoonBit async functions, with no await keyword.
`@tools.call(name, arguments)` is the whole API. `arguments` is the same
JSON object the direct host tool takes, forwarded unchanged; validation and
defaults stay in the host. edit, multi_edit (edits or edits_file), and
web_search (when registered) are the PTC-enabled tools; finish, goal, plan,
job controls, and recursive mbtx calls are unavailable.

Results have content : String, is_error : Bool, data : Json?. Tool errors
are results; transport failures raise and MUST NOT automatically retry a
mutation because its outcome may be unknown. edit and multi_edit data carry
outcome (applied, reverted, rejected, failed, unverified, preview, not_found,
error), the post-write check counts, and on a revert the introduced sites;
with revert_when_errors_above / revert_when_warnings_above (0 = any) the host
restores an edit that introduced more diagnostics than that, so a script can
apply one fix per diagnostic and branch on data.outcome, introduced_count
and removed_count. A script may run moon check --output-json itself to find
its targets. The verified example, run by CI through the real host:

[share/examples/ptc_guarded_edit.mbtx](../../share/examples/ptc_guarded_edit.mbtx)

Search data is {sources:[{url,title?,snippet?,published_at?}],truncated:Bool}.
Missing fields are absent, not empty strings. Keep selected URLs when
printing sources so the final answer can cite them:

[share/examples/ptc_search_filter.mbtx](../../share/examples/ptc_search_filter.mbtx)

Up to 1024 calls per script, four in flight, 64 KiB per request, and 64K
characters per result; a larger edit batch goes through edits_file.
Stateful calls serialize; independent searches can overlap using a MoonBit
task group. Batch related edits with multi_edit to retain its validation
and rollback semantics.

Normal background handoff is unchanged: the script can keep calling tools
after receiving a job ID, and job_output returns the nested calls as
metadata. Only the script's printed output returns to model context. Print
concise selected results, handle is_error explicitly, and stop when further
steps require model judgment.
