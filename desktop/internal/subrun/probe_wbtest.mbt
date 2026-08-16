// Probe tests against a real record file, appended to the way a child does:
// one JSON line at a time, sometimes landing mid-line between polls.

///|
/// A probe over a brand-new record holding only the store's header line —
/// which the probe must read past without mistaking it for an item.
async fn fresh_record(name : String) -> SubrunProbeState {
  let root = @fs.realpath(@fs.tmpdir(prefix="openseek-subrun-probe-\{name}-"))
  let session = "parent-sr-1"
  @fsx.ensure_dir(Path("\{root}/sessions/\{session}"))
  let path = subrun_record_path(root, session)
  @fs.write_file(
    path,
    ({ "version": 1, "id": session, "system_prompt": "s" } : Json).stringify() +
    "\n",
    create_mode=CreateOrTruncate,
  )
  {
    path,
    offset: 0,
    carry: b"",
    anchor: b"",
    steps: 0,
    activity: "",
    watermark: 0,
    pending: [],
  }
}

///|
/// Grow the record the way the store does: append, never rewrite.
async fn append_record(state : SubrunProbeState, text : String) -> Unit {
  let existing = @fs.read_file(state.path).text()
  @fs.write_file(state.path, existing + text, create_mode=CreateOrTruncate)
}

///|
/// One record line. The sequence is explicit because it is what the probe
/// counts by: the store's are monotone, and a repair rewrites surviving
/// events under the SAME numbers they already had.
fn item_line(sequence : Int, kind : String, payload : Json) -> String {
  ({ "sequence": sequence, "item": { "kind": kind, "payload": payload } } : Json).stringify() +
  "\n"
}

///|
fn tool_line(
  sequence : Int,
  id : String,
  name : String,
  brief? : String,
) -> String {
  let payload : Json = match brief {
    Some(brief) =>
      {
        "tool_call_id": id,
        "tool_name": name,
        "content": "…",
        "is_error": false,
        "brief": brief,
      }
    None =>
      {
        "tool_call_id": id,
        "tool_name": name,
        "content": "…",
        "is_error": false,
      }
  }
  item_line(sequence, "tool_result", payload)
}

///|
async test "the probe counts turns and follows the child's last tool call" {
  let state = fresh_record("basics")
  // Nothing appended past the header yet: the header is not progress.
  assert_false(state.poll())
  append_record(state, item_line(1, "user", { "content": "the task" }))
  assert_false(state.poll())
  append_record(state, item_line(2, "assistant", { "content": "thinking" }))
  assert_true(state.poll())
  assert_eq(state.steps, 1)
  assert_eq(state.activity, "")
  append_record(state, tool_line(3, "c1", "read", brief="read moon.mod"))
  assert_true(state.poll())
  assert_eq(state.steps, 1)
  assert_eq(state.activity, "read moon.mod")
  // A briefless result falls back to the tool's name.
  append_record(state, tool_line(4, "c2", "shell"))
  assert_true(state.poll())
  assert_eq(state.activity, "shell")
  // The same brief again is not news, and an idle child moves nothing.
  append_record(state, tool_line(5, "c3", "shell"))
  assert_false(state.poll())
  assert_false(state.poll())
}

///|
async test "a poll landing mid-line waits for the rest of it" {
  let state = fresh_record("torn")
  let line = tool_line(1, "c1", "read", brief="read agent/turn_loop.mbt")
  let cut = line.length() / 2
  append_record(state, line[:cut].to_owned())
  // Half a JSON object is not news, and must not be mistaken for one.
  assert_false(state.poll())
  assert_eq(state.activity, "")
  append_record(state, line[cut:].to_owned())
  assert_true(state.poll())
  assert_eq(state.activity, "read agent/turn_loop.mbt")
}

///|
async test "a rewritten record is re-read from its head" {
  let state = fresh_record("rewritten")
  append_record(state, item_line(1, "assistant", { "content": "one" }))
  assert_true(state.poll())
  assert_eq(state.steps, 1)
  // The store's repair path can rewrite the file shorter than the probe's
  // offset; reading on from that offset would land mid-line forever.
  @fs.write_file(
    state.path,
    ({ "version": 1, "id": "parent-sr-1", "system_prompt": "s" } : Json).stringify() +
    "\n",
    create_mode=CreateOrTruncate,
  )
  // The poll notices the shrink and restarts at the head; only the header is
  // left, which is not progress, and the count of what was already read
  // stands.
  assert_false(state.poll())
  assert_eq(state.steps, 1)
  append_record(state, item_line(2, "assistant", { "content": "again" }))
  assert_true(state.poll())
  assert_eq(state.steps, 2)
}

///|
/// The child records the assistant item that REQUESTS a call before running
/// it, which is the only account of a slow tool while it is slow.
async test "the current tool call is activity, not just the finished one" {
  let state = fresh_record("current")
  append_record(
    state,
    item_line(1, "assistant", {
      "content": "",
      "tool_calls": [
        {
          "id": "c1",
          "name": "shell",
          "arguments": "{\"command\":\"moon check\"}",
        },
      ],
    }),
  )
  assert_true(state.poll())
  assert_eq(state.steps, 1)
  // Without this the lane would read "" for the whole of a long `moon check`.
  assert_eq(state.activity, "shell")
  // The result that eventually lands carries the better text, and wins.
  append_record(
    state,
    tool_line(2, "c1", "shell", brief="shell moon check → ok"),
  )
  assert_true(state.poll())
  assert_eq(state.activity, "shell moon check → ok")
  // An assistant item with no calls leaves the activity alone.
  append_record(state, item_line(3, "assistant", { "content": "done" }))
  assert_true(state.poll())
  assert_eq(state.activity, "shell moon check → ok")
}

///|
/// The store repairs a torn tail by renaming a temp file over the record, and
/// the replacement also carries the newly appended event — so it is usually
/// LONGER than what was read, and no length check can see that. What makes
/// the outcome right is the sequence watermark: the surviving events arrive
/// again under the numbers they already had, and count once.
async test "a same-or-larger rewrite counts survivors once" {
  let state = fresh_record("rewritten-longer")
  append_record(state, item_line(1, "assistant", { "content": "one" }))
  append_record(state, tool_line(2, "c1", "read", brief="read moon.mod"))
  assert_true(state.poll())
  assert_eq(state.steps, 1)
  assert_eq(state.activity, "read moon.mod")
  let grown = state.offset
  // The repair re-serializes the whole record from the child's own state:
  // events 1 and 2 as they were, plus the event whose append tore.
  @fs.write_file(
    state.path,
    ({ "version": 1, "id": "parent-sr-1", "system_prompt": "s" } : Json).stringify() +
    "\n" +
    item_line(1, "assistant", { "content": "one" }) +
    item_line(2, "tool_result", {
      "tool_call_id": "c1",
      "tool_name": "read",
      "content": "…",
      "is_error": false,
      "brief": "read moon.mod",
    }) +
    item_line(3, "assistant", { "content": "two" }) +
    tool_line(4, "c2", "grep", brief="grep is_being_cancelled"),
    create_mode=CreateOrTruncate,
  )
  // Longer than what was read, so nothing about the size says "rewritten".
  assert_true(@fs.read_file(state.path).text().length().to_int64() > grown)
  assert_true(state.poll())
  // Events 1 and 2 arrive a second time and change nothing; only 3 and 4 are
  // new. A count that restarted with the file would say 1 here, and one that
  // trusted the stale offset would say something arbitrary.
  assert_eq(state.steps, 2)
  assert_eq(state.activity, "grep is_being_cancelled")
}

///|
/// The anchor is a hint, not the safety net: even when a replacement happens
/// to leave the same bytes at the same offset — the case a positional check
/// cannot distinguish — the watermark still refuses to count anything twice.
async test "an undetectable replacement still cannot double-count" {
  let state = fresh_record("identical-bytes")
  append_record(state, item_line(1, "assistant", { "content": "one" }))
  append_record(state, item_line(2, "assistant", { "content": "two" }))
  assert_true(state.poll())
  assert_eq(state.steps, 2)
  // Byte-for-byte the same file, rewritten with one more event: every check
  // that looks at bytes or lengths says "just an append".
  let same = @fs.read_file(state.path).text()
  @fs.write_file(
    state.path,
    same + item_line(3, "assistant", { "content": "three" }),
    create_mode=CreateOrTruncate,
  )
  assert_true(state.poll())
  assert_eq(state.steps, 3)
}

///|
fn call(id : String, name : String) -> Json {
  { "id": id, "name": name, "arguments": "{}" }
}

///|
/// A batch runs in call order, so the lane must name the call that is
/// running — not the last one requested, and not the one that just finished
/// while the next is still going.
async test "activity walks a batch in the order it runs" {
  let state = fresh_record("batch")
  append_record(
    state,
    item_line(1, "assistant", {
      "content": "",
      "tool_calls": [call("c1", "read"), call("c2", "shell")],
    }),
  )
  assert_true(state.poll())
  // `read` runs first. Naming `shell` here would name a call that has not
  // started.
  assert_eq(state.activity, "read")
  append_record(state, tool_line(2, "c1", "read", brief="read moon.mod"))
  assert_true(state.poll())
  // `read` is answered and `shell` is now running: showing the finished
  // read's brief would mislabel the whole of the shell call.
  assert_eq(state.activity, "shell")
  append_record(
    state,
    tool_line(3, "c2", "shell", brief="shell moon check → ok"),
  )
  assert_true(state.poll())
  // Nothing left to run: the last result's own brief describes where the
  // child is until its next turn.
  assert_eq(state.activity, "shell moon check → ok")
}

///|
async test "a record that does not exist yet is not an error" {
  let root = @fs.realpath(@fs.tmpdir(prefix="openseek-subrun-probe-missing-"))
  let state = {
    path: subrun_record_path(root, "parent-sr-9"),
    offset: 0,
    carry: b"",
    anchor: b"",
    steps: 0,
    activity: "",
    watermark: 0,
    pending: [],
  }
  // The child is still starting: polls report nothing until it writes.
  assert_false(state.poll())
  assert_false(state.poll())
}
