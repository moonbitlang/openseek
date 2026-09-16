// Generated from ptc_description.md by moon dev_build. DO NOT EDIT.

///|
fn ptc_description() -> String {
  (
    #|
    #|
    #|## Programmatic tool calls (PTC)
    #|
    #|Import the SDK and async runtime explicitly; the host does not rewrite
    #|source. Use ordinary MoonBit async functions, with no await keyword.
    #|`@tools.call(name, arguments)` is the whole API. `arguments` is the same
    #|JSON object the direct host tool takes, forwarded unchanged; validation and
    #|defaults stay in the host. edit, multi_edit (edits or edits_file), and
    #|web_search (when registered) are the PTC-enabled tools; finish, goal, plan,
    #|job controls, and recursive mbtx calls are unavailable.
    #|
    #|Results have content : String, is_error : Bool, data : Json?. Tool errors
    #|are results; transport failures raise and MUST NOT automatically retry a
    #|mutation because its outcome may be unknown. edit and multi_edit data carry
    #|outcome (applied, reverted, rejected, failed, unverified, preview, not_found,
    #|error), the post-write check counts, and on a revert the introduced sites;
    #|with revert_when_errors_above / revert_when_warnings_above (0 = any) the host
    #|restores an edit that introduced more diagnostics than that, so a script can
    #|apply one fix per diagnostic and branch on data.outcome, introduced_count
    #|and removed_count. A script may run moon check --output-json itself to find
    #|its targets. The verified example, run by CI through the real host:
    #|
    #|```mbtx
    #|///|
    #|/// One guarded edit from a script. The host checks the tree before and
    #|/// after the write and restores the file if the edit introduced more
    #|/// diagnostics than the thresholds allow (0 = any); the script reads the
    #|/// outcome from `result.data` instead of parsing prose. Arguments:
    #|/// <path> <old_string> <new_string> [<start_line>]. Verified end to end by
    #|/// a host-backed test that runs it through the real sandbox and host.
    #|import {
    #|  "bobzhang/openseek_tools@0.1.0" @tools,
    #|  "moonbitlang/async",
    #|  "moonbitlang/core/env",
    #|  "moonbitlang/core/string",
    #|}
    #|
    #|///|
    #|async fn main {
    #|  let args = @env.args()[1:]
    #|  guard args is [path, old_string, new_string, ..] else {
    #|    fail(
    #|      "usage: ptc_guarded_edit.mbtx <path> <old_string> <new_string> [<start_line>]",
    #|    )
    #|  }
    #|  let start_line : Int = match args {
    #|    [_, _, _, line, ..] =>
    #|      @string.from_str(line) catch { _ => fail("start_line must be an integer") }
    #|    _ => 1
    #|  }
    #|  // `arguments` is the JSON object the direct edit tool takes, forwarded
    #|  // unchanged; the host validates it. The guards are integer thresholds on
    #|  // the diagnostics the edit introduced, counted by identity so the edit's
    #|  // own line shifts never count: 0 reverts on any, absent means no guard.
    #|  let result = @tools.call("edit", {
    #|    "path": path,
    #|    "start_line": start_line,
    #|    "old_string": old_string,
    #|    "new_string": new_string,
    #|    "revert_when_errors_above": 0,
    #|    "revert_when_warnings_above": 0,
    #|  })
    #|  // A tool error is a result (`is_error` set, `content` explains). Only a
    #|  // transport failure raises, and a mutation may already have happened
    #|  // then, so a script never retries one blindly.
    #|  match result.data {
    #|    Some(
    #|      {
    #|        "outcome": "applied",
    #|        "check": { "warning_count": Number(warnings, ..), .. },
    #|        ..
    #|      }
    #|    ) => println("applied; \{warnings.to_int()} warning(s) remain")
    #|    Some({ "outcome": "applied", .. }) => println("applied")
    #|    // A revert whose restore failed (a concurrent save, an IO error) leaves
    #|    // the file in an unknown state: report that first, with the host's
    #|    // explanation, never as an ordinary revert.
    #|    Some({ "outcome": "reverted", "restore_failed": true, .. }) =>
    #|      println("reverted but NOT restored: \{result.content}")
    #|    Some(
    #|      {
    #|        "outcome": "reverted",
    #|        "reason": String(reason),
    #|        "introduced_count": {
    #|          "errors": Number(errors, ..),
    #|          "warnings": Number(warnings, ..),
    #|          ..
    #|        },
    #|        ..
    #|      }
    #|    ) =>
    #|      println(
    #|        "reverted: \{reason} (\{errors.to_int()} error(s), \{warnings.to_int()} warning(s) introduced)",
    #|      )
    #|    Some({ "outcome": String(outcome), .. }) =>
    #|      println("\{outcome}: \{result.content}")
    #|    _ => println("no data: \{result.content}")
    #|  }
    #|  // Only what the script prints reaches the model; the nested call itself is
    #|  // kept in the transcript. Every call finishes before main returns.
    #|}
    #|```
    #|
    #|Search data is {sources:[{url,title?,snippet?,published_at?}],truncated:Bool}.
    #|Missing fields are absent, not empty strings. Keep selected URLs when
    #|printing sources so the final answer can cite them:
    #|
    #|```mbtx
    #|///|
    #|/// A search from a script, filtered before anything reaches the model: only
    #|/// printed output enters the context, so the script prints the selected
    #|/// evidence with its URL and keeps whatever affects the answer, such as a
    #|/// truncated result set. Arguments: <query> [<domain>]; a source is kept
    #|/// when its URL contains <domain>. Verified by a host-backed test with a
    #|/// stub search tool.
    #|import {
    #|  "bobzhang/openseek_tools@0.1.0" @tools,
    #|  "moonbitlang/async",
    #|  "moonbitlang/core/env",
    #|}
    #|
    #|///|
    #|async fn main {
    #|  let args = @env.args()[1:]
    #|  guard args is [query, ..] else {
    #|    fail("usage: ptc_search_filter.mbtx <query> [<domain>]")
    #|  }
    #|  // An absent option is `None`, not an empty string.
    #|  let domain : String? = match args {
    #|    [_, domain, ..] => Some(domain)
    #|    _ => None
    #|  }
    #|  let result = @tools.call("web_search", { "query": query })
    #|  if result.is_error {
    #|    println("search failed: \{result.content}")
    #|    return
    #|  }
    #|  // Search data is {sources: [{url, title?, snippet?, published_at?}],
    #|  // truncated: Bool}. Optional fields are absent, never empty strings, so a
    #|  // pattern with `..` reads what is there and falls back for the rest.
    #|  guard result.data
    #|    is Some({ "sources": Array(sources), "truncated": truncated, .. }) else {
    #|    println("no structured sources: \{result.content}")
    #|    return
    #|  }
    #|  let mut shown = 0
    #|  for source in sources {
    #|    guard source is { "url": String(url), .. } else { continue }
    #|    if domain is Some(domain) && !url.contains(domain) {
    #|      continue
    #|    }
    #|    let title = match source {
    #|      { "title": String(title), .. } => title
    #|      _ => url
    #|    }
    #|    println("- \{title} — \{url}")
    #|    shown += 1
    #|  }
    #|  println("\{shown} of \{sources.length()} source(s) shown for \{query}")
    #|  if truncated is true {
    #|    println("note: the search results were truncated")
    #|  }
    #|}
    #|```
    #|
    #|Up to 1024 calls per script, four in flight, 64 KiB per request, and 64K
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
    #|
  )
}
