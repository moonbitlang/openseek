///|
/// `sample_session` round-tripped through the durable-log parse path with an
/// empty system prompt — the "clean parsed session" several render tests use.
fn clean_sample_session() -> @agent_session.Session {
  @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="",
  )
}

///|
/// Build a session that exercises every event kind, then serialize it back to
/// the on-disk session-file event form so the parser is tested against exactly what
/// the store writes.
fn sample_session() -> @agent_session.Session {
  let s0 = @agent_session.Session(
    SessionId("demo"),
    system_prompt="You are a helpful agent.",
  )
  let s1 = s0.append(User(UserMessage("list the files")))
  let s2 = s1.append(
    Assistant(
      AssistantMessage(
        "I'll run ls.",
        tool_calls=[
          ToolCall(id="call_1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ],
        reasoning_content="The user wants a directory listing.",
      ),
    ),
  )
  let s3 = s2.append(
    Tool(
      ToolResult(
        tool_call_id="call_1",
        tool_name="shell",
        content="README.md\nsrc",
      ),
    ),
  )
  let s4 = s3.append(Runtime(RuntimeNotice("plan reminder: run tests")))
  s4.append(Terminal(Finished("Here are your files: README.md, src.")))
}

///|
/// Serialize a session to the append-only JSONL text the store persists.
fn events_jsonl(session : @agent_session.Session) -> String {
  let out = StringBuilder()
  for event in session.events() {
    out <+ "\{event.to_json().stringify()}\n"
  }
  out.to_string()
}

///|
#warnings("-alert_unstable")
fn render(html : @html.Html) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(html))
}

///|
/// Raw-view HTML for a session holding a single tool call. The session and call
/// ids never appear in these assertions, so they are fixed.
fn render_tool_call(name : String, arguments : String) -> String {
  let session = @agent_session.Session(SessionId("s"), system_prompt="").append(
    Assistant(
      AssistantMessage("", tool_calls=[ToolCall(id="c1", name~, arguments~)]),
    ),
  )
  render(@viz.render_session(session, RawLog))
}

///|
/// Raw-view HTML for two successive `plan` calls — a baseline plan followed by a
/// revised one — the shape the plan-diff rendering (rewrite notes, delta chips)
/// is exercised against.
fn two_plan_calls_raw(before : String, after : String) -> String {
  let session = @agent_session.Session(SessionId("plan2"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="p1", name="plan", arguments=before),
        ]),
      ),
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="p2", name="plan", arguments=after),
        ]),
      ),
    )
  render(@viz.render_session(session, RawLog))
}

///|
/// Compact away the sequence-2 event (a tool result in these fixtures) with a
/// "covered" summary — the projection then heals the call with a synthetic
/// result the model never saw.
fn compact_second_event(
  session : @agent_session.Session,
) -> @agent_session.Session raise {
  session.compact(content="covered", from_sequence=2, to_sequence=2)
}

///|
/// A session whose tool result failed, plus a tool call with arguments and one
/// without, to exercise the fold/flag rendering.
fn error_tool_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("e"), system_prompt="")
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ToolCall(id="c2", name="noop", arguments="{}"),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="c1",
        tool_name="shell",
        content="boom",
        is_error=true,
      ),
    ),
  )
}

///|
fn multi_step_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("steps"), system_prompt="system")
  .append(User(UserMessage("start")))
  .append(
    Assistant(
      AssistantMessage("checking", tool_calls=[
        ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"pwd\"}"),
      ]),
    ),
  )
  .append(
    Tool(ToolResult(tool_call_id="c1", tool_name="shell", content="/repo")),
  )
  .append(Assistant(AssistantMessage("final answer")))
  .append(Terminal(Finished("final answer")))
}

///|
fn occurrences(text : String, needle : String) -> Int {
  text.split(needle).count() - 1
}

///|
/// Two calls to the same tool in one assistant turn, each with its own result —
/// the exact case where the separate result cards were previously
/// indistinguishable (both just `Tool result · read`).
fn multi_call_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("mc"), system_prompt="")
  .append(User(UserMessage("read both")))
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(id="r1", name="read", arguments="{\"path\":\"a.txt\"}"),
        ToolCall(id="r2", name="read", arguments="{\"path\":\"b.txt\"}"),
      ]),
    ),
  )
  .append(Tool(ToolResult(tool_call_id="r1", tool_name="read", content="AAA")))
  .append(Tool(ToolResult(tool_call_id="r2", tool_name="read", content="BBB")))
  .append(Terminal(Finished("done")))
}

///|
/// Ids that must NOT be paired: an empty id (a streaming glitch can leave one),
/// a duplicate call id, and an orphan result whose id matches no call.
fn unpairable_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("edge"), system_prompt="")
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(id="", name="noop", arguments="{}"),
        ToolCall(id="dup", name="a", arguments="{}"),
        ToolCall(id="dup", name="b", arguments="{}"),
      ]),
    ),
  )
  .append(
    Tool(ToolResult(tool_call_id="orphan", tool_name="ghost", content="?")),
  )
}

///|
/// One call whose id has TWO results — the result side is ambiguous, so the raw
/// view (which shows both results) must not pair it.
fn duplicate_result_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("dupres"), system_prompt="")
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(id="d", name="read", arguments="{\"path\":\"x\"}"),
      ]),
    ),
  )
  .append(Tool(ToolResult(tool_call_id="d", tool_name="read", content="one")))
  .append(Tool(ToolResult(tool_call_id="d", tool_name="read", content="two")))
}

///|
/// A unique, non-empty call id with no result event: raw has no result to pair,
/// but the model projection heals the dangling call with a synthetic result, so
/// the model view can (and should) pair the two.
fn dangling_call_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("dangle"), system_prompt="")
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(id="only", name="read", arguments="{\"path\":\"x\"}"),
      ]),
    ),
  )
  .append(Terminal(Aborted("stopped")))
}

///|
fn finish_tool_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("finish"), system_prompt="system")
  .append(User(UserMessage("start")))
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(
          id="finish_1",
          name="finish",
          arguments="{\"answer\":\"done\"}",
        ),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="finish_1",
        tool_name="finish",
        content="finished: done",
      ),
    ),
  )
  .append(Terminal(Finished("done")))
}

///|
test "tool calls fold their arguments, empty args stay flat" {
  let html = render(@viz.render_session(error_tool_session(), RawLog))
  // A call with arguments folds: the name becomes a <summary>, args hide in the
  // collapsed <details> (no `open` attribute) yet are still in the DOM.
  // c1 (shell) has args and its result failed, so its fold carries the failed tag.
  // It also pairs with a result, so it gets a `tool-call-1` anchor.
  assert_true(
    html.contains(
      "<details class=\"tool-call tool-call-failed\" id=\"tool-call-1\">",
    ),
  )
  assert_true(html.contains("<summary class=\"tool-call-name\">"))
  assert_true(html.contains("shell"))
  assert_true(html.contains("cmd"))
  // A call with no meaningful arguments ({}) renders flat — nothing to fold.
  assert_true(
    html.contains("<div class=\"tool-call\"><div class=\"tool-call-name\">"),
  )
}

///|
test "tool args render verbatim, keeping the raw JSON for debugging" {
  // A write_file-style call: the body is a multi-line string. The friendly view
  // must show it as real text (no JSON quoting/escaping), while the original
  // pretty-printed JSON stays in the DOM, hidden behind the `.show-original`
  // toggle, so the raw escaped form is still available for debugging.
  let html = render_tool_call(
    "write_file", "{\"path\":\"notes.txt\",\"content\":\"alpha\\nbeta\"}",
  )
  // Friendly form: a key/value row per field, the body shown verbatim with a real
  // newline — not the JSON-escaped `alpha\nbeta`.
  assert_true(html.contains("class=\"tool-call-args-rendered\""))
  assert_true(html.contains("class=\"arg-key\">path"))
  assert_true(html.contains("class=\"arg-key\">content"))
  assert_true(html.contains("notes.txt"))
  assert_true(html.contains("class=\"arg-value\">alpha\nbeta</pre>"))
  // Original form preserved for debugging: the escaped JSON string.
  assert_true(html.contains("tool-call-args-original"))
  assert_true(html.contains("alpha\\nbeta"))
}

///|
test "mbtx source uses editor token classes and keeps original JSON" {
  let arguments =
    #|{"source":"fn main {\n  let greeting = \"<hello>\"\n}","target":"js"}
  let html = render_tool_call("mbtx", arguments)
  assert_true(html.contains("class=\"arg-value moonbit-source\""))
  assert_true(html.contains("class=\"language-moonbit moonbit-code\""))
  // Each source line is numbered so the run's `line:column` diagnostics can
  // be followed without counting lines.
  assert_true(html.contains("class=\"moonbit-gutter\">1</span>"))
  assert_true(html.contains("class=\"moonbit-gutter\">3</span>"))
  assert_true(html.contains("<span class=\"mtk3\">fn</span>"))
  assert_true(html.contains("<span class=\"mtk3\">let</span>"))
  assert_true(html.contains("class=\"mtk5\""))
  // Token text is still escaped by Rabbita rather than installed as raw HTML.
  assert_true(html.contains("&lt;hello&gt;"))
  assert_false(html.contains("<hello>"))
  // Viz's global Rendered / Original toggle keeps the raw payload in the DOM.
  assert_true(html.contains("tool-call-args-original"))
  assert_true(html.contains("target"))
}

///|
/// The export renders the whole program: a source past the transcript
/// helper's 101-line clamp still shows every line under its true number,
/// with no skip marker.
test "a long mbtx program keeps every numbered line in the export" {
  let lines : Array[String] = []
  for index in 0..<120 {
    lines.push("let x\{index} = \{index}")
  }
  let arguments : Json = { "source": lines.join("\n"), "target": "js" }
  let html = render_tool_call("mbtx", arguments.stringify())
  assert_true(html.contains("class=\"moonbit-gutter\">120</span>"))
  assert_false(html.contains("skipped"))
}

///|
test "MoonBit read results highlight source in raw and model views" {
  let session = @agent_session.Session(SessionId("read-mbt"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="r1",
            name="read",
            arguments="{\"path\":\"src/main.mbt\"}",
          ),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="r1",
          tool_name="read",
          content=(
            #|1 |fn main {
            #|2 |  println("hi")
            #|3 |}
            #|<system>start_line=1 shown_lines=3 total_lines=3 truncated=false</system>
          ),
          brief="read main.mbt",
        ),
      ),
    )
  for mode in [@viz.RawLog, ModelView] {
    let html = render(@viz.render_session(session, mode))
    assert_true(html.contains("read-moonbit-output"))
    assert_true(html.contains("class=\"read-moonbit-gutter\">1</span>"))
    assert_true(html.contains("<span class=\"mtk3\">fn</span>"))
    assert_true(html.contains("class=\"read-moonbit-status\""))
    assert_true(html.contains("class=\"content tool-call-args-original\""))
    assert_true(html.contains("1 |fn main"))
  }
}

///|
test "non-object tool args fall back to JSON in both forms" {
  // Arguments that are not a JSON object (here a bare array) have no key/value
  // fields, so the friendly view falls back to pretty JSON rather than inventing
  // a structure.
  let html = render_tool_call("batch", "[1,2,3]")
  assert_true(html.contains("class=\"tool-call-args tool-call-args-rendered\""))
  assert_true(html.contains("tool-call-args-original"))
  assert_false(html.contains("arg-key"))
}

///|
test "a nested object argument recurses into indented key/value rows" {
  // A nested object must not collapse to one escaped JSON blob: it recurses
  // into the same key/value rows, indented, with string leaves shown verbatim.
  let html = render_tool_call(
    "configure", "{\"name\":\"probe\",\"opts\":{\"retries\":3,\"label\":\"fast\"}}",
  )
  assert_true(html.contains("class=\"arg-key\">name"))
  assert_true(html.contains("class=\"arg-key\">opts"))
  // The nested object recurses rather than dumping stringified JSON.
  assert_true(html.contains("class=\"arg-object\""))
  assert_true(html.contains("class=\"arg-key\">retries"))
  assert_true(html.contains("class=\"arg-key\">label"))
  assert_true(html.contains("class=\"arg-value-inline\">fast"))
}

///|
test "an array-of-objects argument renders one item per element" {
  // Each array element renders as its own item, recursing into the element's
  // fields — the general shape `multi_edit`'s `edits` benefits from.
  let html = render_tool_call(
    "batch", "{\"steps\":[{\"op\":\"add\",\"n\":1},{\"op\":\"del\",\"n\":2}]}",
  )
  assert_true(html.contains("class=\"arg-key\">steps"))
  assert_true(html.contains("class=\"arg-array\""))
  // Two elements → two items, each with its own recursed fields.
  assert_eq(occurrences(html, "class=\"arg-item\""), 2)
  assert_true(html.contains("class=\"arg-value-inline\">add"))
  assert_true(html.contains("class=\"arg-value-inline\">del"))
}

///|
test "edit args gain a synthesized generated_diff, keeping the originals" {
  // The original old_string/new_string rows are kept AND a generated_diff field
  // is added, rendered as a colored diff (- removed / + added).
  let html = render_tool_call(
    "edit", "{\"path\":\"lib/parser.mbt\",\"old_string\":\"args.length()\",\"new_string\":\"args.len()\",\"start_line\":12}",
  )
  // Originals kept.
  assert_true(html.contains("class=\"arg-key\">old_string"))
  assert_true(html.contains("class=\"arg-key\">new_string"))
  // New synthesized field, shown as a diff.
  assert_true(html.contains("class=\"arg-key\">generated_diff"))
  assert_true(html.contains("class=\"diff-del\">- args.length()"))
  assert_true(html.contains("class=\"diff-add\">+ args.len()"))
  // The raw JSON (Original toggle) is untouched — no synthesized field there.
  assert_false(html.contains("\\\"generated_diff\\\""))
}

///|
test "multi_edit gains a generated_diff per edit" {
  let html = render_tool_call(
    "multi_edit", "{\"edits\":[{\"file\":\"a.mbt\",\"old_string\":\"foo\",\"new_string\":\"bar\",\"start_line\":1},{\"file\":\"b.mbt\",\"old_string\":\"x\",\"new_string\":\"y\",\"start_line\":2}]}",
  )
  // One diff per edit.
  assert_eq(occurrences(html, "class=\"arg-key\">generated_diff"), 2)
  assert_true(html.contains("class=\"diff-del\">- foo"))
  assert_true(html.contains("class=\"diff-add\">+ bar"))
  assert_true(html.contains("class=\"diff-del\">- x"))
  assert_true(html.contains("class=\"diff-add\">+ y"))
}

///|
test "an insertion edit diffs as added-only lines" {
  // Empty old_string → the generated_diff is all `+` lines, shown verbatim
  // across real newlines, with no removed side.
  let html = render_tool_call(
    "edit", "{\"path\":\"a.mbt\",\"old_string\":\"\",\"new_string\":\"let x = 1\\nlet y = 2\",\"start_line\":5}",
  )
  assert_true(html.contains("class=\"diff-add\">+ let x = 1"))
  assert_true(html.contains("class=\"diff-add\">+ let y = 2"))
  assert_false(html.contains("class=\"diff-del\""))
}

///|
test "a failed tool call is tagged so errors-only keeps its call card" {
  // error_tool_session: c1 (shell) failed. Its call gets `tool-call-failed`, the
  // hook the errors-only stylesheet uses to keep the assistant card holding the
  // call — so the call cell and the error result cell both stay (not merged).
  let raw = render(@viz.render_session(error_tool_session(), RawLog))
  assert_true(raw.contains("tool-call-failed"))
  let model = render(@viz.render_session(error_tool_session(), ModelView))
  assert_true(model.contains("tool-call-failed"))
  // A clean session tags no call as failed.
  let clean = clean_sample_session()
  assert_false(
    render(@viz.render_session(clean, RawLog)).contains("tool-call-failed"),
  )
}

///|
/// mbtx failure-stage fixtures: a build-stage failure (staged brief), a
/// wasm-default runtime failure, and a js single-shot failure whose one exit
/// code must claim neither stage.
fn mbtx_stage_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("mbtx-stage"), system_prompt="")
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(
          id="b1",
          name="mbtx",
          arguments="{\"source\":\"fn main {  }\"}",
        ),
        ToolCall(
          id="r1",
          name="mbtx",
          arguments="{\"source\":\"fn main {  }\"}",
        ),
        ToolCall(
          id="j1",
          name="mbtx",
          arguments="{\"source\":\"fn main {  }\",\"target\":\"js\"}",
        ),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="b1",
        tool_name="mbtx",
        content="diag",
        is_error=true,
        brief="mbtx (build failed, exit=1)",
      ),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="r1",
        tool_name="mbtx",
        content="trap",
        is_error=true,
        brief="mbtx (exit=1)",
      ),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="j1",
        tool_name="mbtx",
        content="js diag",
        is_error=true,
        brief="mbtx (exit=1)",
      ),
    ),
  )
}

///|
/// The stage words and the filter hooks: a build failure tags its call
/// (`tool-call-build-failed`) and its result card (`build-failed`) — what the
/// build-errors-only stylesheet keys on — while the wasm runtime failure gets
/// the run word and the js single-shot failure claims neither stage.
test "mbtx rows name their failure stage and tag the filter hooks" {
  let raw = render(@viz.render_session(mbtx_stage_session(), RawLog))
  assert_true(raw.contains("tool-call-build-failed"))
  assert_true(raw.contains("build error"))
  assert_true(raw.contains("card tool error build-failed"))
  assert_true(raw.contains("🚩 build error"))
  assert_true(raw.contains("tool-call-run-failed"))
  assert_true(raw.contains("runtime error"))
  // Exactly one call carries each stage class: the js failure is neither.
  assert_eq(raw.split("tool-call-build-failed").length(), 2)
  assert_eq(raw.split("tool-call-run-failed").length(), 2)
  // The model view renders the same tags from the projected maps.
  let model = render(@viz.render_session(mbtx_stage_session(), ModelView))
  assert_true(model.contains("tool-call-build-failed"))
  assert_true(model.contains("card tool error build-failed"))
  assert_true(model.contains("🚩 build error"))
  // A clean session tags nothing.
  let clean = render(@viz.render_session(clean_sample_session(), RawLog))
  assert_false(clean.contains("tool-call-build-failed"))
  assert_false(clean.contains("tool-call-run-failed"))
}

///|
test "rendered_build_error_count counts staged build failures per mode" {
  let session = mbtx_stage_session()
  assert_eq(@viz.rendered_build_error_count(session, RawLog), 1)
  assert_eq(@viz.rendered_build_error_count(session, ModelView), 1)
  assert_eq(@viz.rendered_build_error_count(clean_sample_session(), RawLog), 0)
}

///|
test "failed tool result is folded and red-flagged" {
  let html = render(@viz.render_session(error_tool_session(), RawLog))
  // Folded by default (a <details> with no `open`), tagged as an error, and the
  // summary carries the red flag so a collapsed failure still stands out.
  assert_true(
    html.contains("<details class=\"card tool error\" id=\"tool-result-1\">"),
  )
  assert_false(
    html.contains(
      "<details class=\"card tool error\" id=\"tool-result-1\" open>",
    ),
  )
  assert_true(html.contains("class=\"tool-flag\">🚩 failed"))
  assert_true(html.contains("Tool error · shell"))
  assert_true(html.contains("boom"))
}

///|
test "model view recovers the error flag the projection drops" {
  // The model projection keys a tool message by id only and drops is_error, but
  // the view correlates back to the durable ToolResult, so a failed tool (e.g. a
  // non-zero exit) is red-flagged in the model view too — with its tool name.
  let model = render(@viz.render_session(error_tool_session(), ModelView))
  assert_true(
    model.contains("<details class=\"card tool error\" id=\"tool-result-1\">"),
  )
  assert_true(model.contains("class=\"tool-flag\">🚩 failed"))
  assert_true(model.contains("Tool error · shell"))
}

///|
test "model view shows relative event timestamps" {
  let session = @agent_session.Session(
      SessionId("time"),
      system_prompt="system",
    )
    .append(User(UserMessage("inspect")), unix_ms=100000L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"moon test\"}"),
        ]),
      ),
      unix_ms=101500L,
    )
    .append(
      Tool(ToolResult(tool_call_id="c1", tool_name="shell", content="ok")),
      unix_ms=103200L,
    )
    .append(Terminal(Finished("done")), unix_ms=170300L)
  let html = render(@viz.render_session(session, ModelView))
  assert_true(html.contains("class=\"card-ts\">+0.0s"))
  assert_true(html.contains("class=\"card-ts\">+1.5s"))
  assert_true(html.contains("class=\"card-ts\">+3.2s"))
  assert_true(html.contains("class=\"card-ts\">+70.3s"))
  assert_false(html.contains("class=\"card-ts\">+1m 10.3s"))
}

///|
test "assistant cards show agent step progress" {
  let session = multi_step_session()
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("class=\"card-step\">Step 1/2"))
  assert_true(raw.contains("class=\"card-step\">Step 2/2"))
  inspect(occurrences(raw, "class=\"card-step\""), content="2")
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("class=\"card-step\">Step 1/2"))
  assert_true(model.contains("class=\"card-step\">Step 2/2"))
  inspect(occurrences(model, "class=\"card-step\""), content="2")
  assert_false(model.contains("Step 3/2"))
}

///|
test "finish tool terminal does not add an extra step" {
  let session = finish_tool_session()
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("class=\"card-step\">Step 1/1"))
  inspect(occurrences(raw, "class=\"card-step\""), content="1")
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("class=\"card-step\">Step 1/1"))
  inspect(occurrences(model, "class=\"card-step\""), content="1")
  assert_false(model.contains("Step 2/2"))
}

///|
test "only assistant responses add step badges" {
  let session = @agent_session.Session(
      SessionId("review-on-finish"),
      system_prompt="system",
    )
    .append(User(UserMessage("finish")))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_finish",
          tool_name="submit_report",
          content="finished: done",
        ),
      ),
    )
    .append(Runtime(RuntimeNotice("[review] goal-met audit: clean")))
    .append(Runtime(RuntimeNotice(@agent_session.GoalClearedNotice)))
    .append(Terminal(Finished("done")))
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("class=\"card-step\">Step 1/1"))
  inspect(occurrences(raw, "class=\"card-step\""), content="1")
  let continued = @agent_session.Session(
      SessionId("runtime-continuation"),
      system_prompt="system",
    )
    .append(User(UserMessage("finish")))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_finish",
          tool_name="submit_report",
          content="finished: first answer",
        ),
      ),
    )
    .append(Runtime(RuntimeNotice("background job completed")))
    .append(Assistant(AssistantMessage("second answer")))
    .append(Terminal(Finished("second answer")))
  let continued_raw = render(@viz.render_session(continued, RawLog))
  assert_true(continued_raw.contains("class=\"card-step\">Step 1/2"))
  assert_true(continued_raw.contains("class=\"card-step\">Step 2/2"))
  inspect(occurrences(continued_raw, "class=\"card-step\""), content="2")
}

///|
test "checkpoint replay assistants do not add an extra step" {
  let session = @agent_session.Session(
      SessionId("checkpoint-replay"),
      system_prompt="system",
    )
    .append(User(UserMessage("go")))
    .append(Assistant(AssistantMessage("first")))
    .append(
      Summary(
        SessionSummary(content="checkpoint", from_sequence=1, to_sequence=2),
      ),
    )
    .append(Assistant(AssistantMessage("first", is_replay=true)))
    .append(User(UserMessage("continue")))
    .append(Assistant(AssistantMessage("second")))
    .append(Terminal(Finished("second")))
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("class=\"card-step\">Step 1/2"))
  assert_true(raw.contains("class=\"card-step\">Step 2/2"))
  inspect(occurrences(raw, "class=\"card-step\""), content="2")
  let model = render(@viz.render_session(session, ModelView))
  // The summary projects in place of the covered first assistant. The replay
  // keeps its prose available to the model but owns no new step badge.
  assert_false(model.contains("class=\"card-step\">Step 1/2"))
  assert_true(model.contains("class=\"card-step\">Step 2/2"))
  inspect(occurrences(model, "class=\"card-step\""), content="1")
}

///|
test "model view does not flag a result the projection skipped" {
  // Compact away only the tool result (seq 2): the projection then heals the
  // dangling call c1 with a synthetic error message, so the model never saw the
  // real "boom" result. The view must not attach that result's flag/name to the
  // synthetic message — it would misrepresent what the model was fed.
  let compacted = compact_second_event(error_tool_session())
  let model = render(@viz.render_session(compacted, ModelView))
  assert_true(model.contains("previous agent process exited"))
  assert_false(model.contains("tool-flag"))
  assert_false(model.contains("Tool error · shell"))
}

///|
test "successful tool result folds without a flag" {
  // sample_session's tool result is a success; it should fold but carry no flag.
  let session = clean_sample_session()
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(
    raw.contains("<details class=\"card tool\" id=\"tool-result-1\">"),
  )
  assert_false(raw.contains("tool-flag"))
  // Model view folds its tool result too (no flag — the projection drops it).
  let model = render(@viz.render_session(session, ModelView))
  assert_true(
    model.contains("<details class=\"card tool\" id=\"tool-result-1\">"),
  )
  assert_true(model.contains("Tool result"))
}

///|
test "tool call shows the brief its result recorded" {
  let session = @agent_session.Session(SessionId("b"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="shell",
          content="exit=0\na",
          brief="ran ls → 1 file",
        ),
      ),
    )
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("tool-call-brief"))
  assert_true(raw.contains("ran ls → 1 file"))
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("ran ls → 1 file"))
  // A *successful* result with no brief produces no brief span on its call.
  let clean = clean_sample_session()
  assert_false(
    render(@viz.render_session(clean, RawLog)).contains("tool-call-brief"),
  )
}

///|
test "a failed tool call is flagged on the folded call line" {
  // error_tool_session: c1 (shell) failed with no brief -> flagged with 🚩.
  let raw = render(@viz.render_session(error_tool_session(), RawLog))
  assert_true(raw.contains("tool-call-brief"))
  assert_true(raw.contains("🚩"))
  // A failed result that carries a brief shows the brief and the flag, in both
  // views.
  let with_brief = @agent_session.Session(SessionId("fb"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="r1", name="read", arguments="{\"path\":\"x.txt\"}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="r1",
          tool_name="read",
          content="error reading x.txt: missing",
          is_error=true,
          brief="read x.txt",
        ),
      ),
    )
  assert_true(
    render(@viz.render_session(with_brief, RawLog)).contains("read x.txt 🚩"),
  )
  assert_true(
    render(@viz.render_session(with_brief, ModelView)).contains(
      "read x.txt 🚩",
    ),
  )
}

///|
test "model view omits a brief whose result was compacted away" {
  let session = @agent_session.Session(SessionId("cb"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="shell",
          content="files",
          brief="ran ls → 3 files",
        ),
      ),
    )
  // Compact away only the result (seq 2): the model projection heals the call
  // with a synthetic result, so the model never saw this brief.
  let compacted = compact_second_event(session)
  // Raw shows the durable brief on the call; the model view must not.
  assert_true(
    render(@viz.render_session(compacted, RawLog)).contains(
      "ran ls → 3 files",
    ),
  )
  assert_false(
    render(@viz.render_session(compacted, ModelView)).contains(
      "ran ls → 3 files",
    ),
  )
}

///|
test "turn header badges failed tools" {
  let html = render(@viz.render_session(error_tool_session(), RawLog))
  assert_true(html.contains("turn-error-badge"))
  assert_true(html.contains("🚩 1 error"))
}

///|
test "rendered_error_count matches the failures each view draws" {
  let failing = error_tool_session()
  inspect(@viz.rendered_error_count(failing, RawLog), content="1")
  inspect(@viz.rendered_error_count(failing, ModelView), content="1")
  let clean = clean_sample_session()
  inspect(@viz.rendered_error_count(clean, RawLog), content="0")
  inspect(@viz.rendered_error_count(clean, ModelView), content="0")
}

///|
test "model error count excludes a compacted-away failure raw still shows" {
  let compacted = compact_second_event(error_tool_session())
  // Raw still renders the durable errored result; the model view healed the
  // dangling call, so it has no error card to count.
  inspect(@viz.rendered_error_count(compacted, RawLog), content="1")
  inspect(@viz.rendered_error_count(compacted, ModelView), content="0")
}

///|
test "parse round-trips every event kind" {
  let text = events_jsonl(sample_session())
  let parsed = @viz.parse_events(text)
  inspect(parsed.events.length(), content="5")
  inspect(parsed.errors.length(), content="0")
  inspect(parsed.partial_tail, content="false")
}

///|
test "parse tolerates a truncated final line" {
  let text = "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"assi"
  let parsed = @viz.parse_events(text)
  inspect(parsed.events.length(), content="1")
  inspect(parsed.errors.length(), content="0")
  inspect(parsed.partial_tail, content="true")
}

///|
test "parse records a bad interior line without aborting" {
  let text = "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\nnot json at all\n{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"done\"}}}\n"
  let parsed = @viz.parse_events(text)
  inspect(parsed.events.length(), content="2")
  inspect(parsed.errors.length(), content="1")
  inspect(parsed.errors[0].line_number, content="2")
  inspect(parsed.partial_tail, content="false")
}

///|
test "raw view renders each event kind" {
  let session = @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="You are a helpful agent.",
  )
  let html = render(@viz.render_session(session, RawLog))
  assert_true(html.contains("Turn 1"))
  assert_true(html.contains("class=\"card user\""))
  assert_true(html.contains("class=\"card assistant\""))
  assert_true(html.contains("reasoning"))
  assert_true(html.contains("shell"))
  assert_true(html.contains("Tool result"))
  assert_true(html.contains("Runtime notice"))
  assert_true(html.contains("badge-finished"))
}

///|
test "model view substitutes a summary for the events it covers" {
  // A session whose summary covers the first two events: the model projection
  // should show the summary text and drop the covered user/assistant content.
  let base = @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="SYS-PROMPT-MARKER",
  )
  let compacted = base.compact(
    content="SUMMARY-MARKER: user asked for files; agent planned ls.",
    from_sequence=1,
    to_sequence=2,
  )
  let model_html = render(@viz.render_session(compacted, ModelView))
  assert_true(model_html.contains("System prompt"))
  assert_true(model_html.contains("SYS-PROMPT-MARKER"))
  assert_true(model_html.contains("SUMMARY-MARKER"))
  // The assistant's planning line is covered by the summary, so the model view
  // must not replay it.
  assert_true(!model_html.contains("I'll run ls."))
  // The raw view still shows everything, including the covered line.
  let raw_html = render(@viz.render_session(compacted, RawLog))
  assert_true(raw_html.contains("I'll run ls."))
  assert_true(raw_html.contains("Summary"))
}

///|
test "notices surface partial tails and bad lines" {
  let parsed = @viz.parse_events(
    (
      #|garbage line
      #|{"sequence":1,"item":{"kind":"user","payload":{"content":"hi"}}}
      #|{bad tail
    ),
  )
  let html = render(@viz.render_notices(parsed))
  assert_true(html.contains("could not be decoded"))
  assert_true(html.contains("trailing partial line"))
}

///|
test "each tool call and its result share a pairing anchor and cross-link" {
  // Both raw and model view must connect each call to its own result so two
  // same-tool calls in one turn are no longer ambiguous.
  for mode in [@viz.RawLog, ModelView] {
    let html = render(@viz.render_session(multi_call_session(), mode))
    // Each call and its result carry the anchor the other links to.
    assert_true(html.contains("id=\"tool-call-1\""))
    assert_true(html.contains("id=\"tool-call-2\""))
    assert_true(html.contains("id=\"tool-result-1\""))
    assert_true(html.contains("id=\"tool-result-2\""))
    // The call links forward to its result; the result links back to the call.
    assert_true(html.contains("href=\"#tool-result-1\""))
    assert_true(html.contains("href=\"#tool-result-2\""))
    assert_true(html.contains("href=\"#tool-call-1\""))
    assert_true(html.contains("href=\"#tool-call-2\""))
    // The same `call N` chip labels both sides of each pair (call + result).
    inspect(occurrences(html, ">call 1</a>"), content="2")
    inspect(occurrences(html, ">call 2</a>"), content="2")
    inspect(occurrences(html, "class=\"tool-link\""), content="4")
    // Each anchor id is emitted exactly once (no duplicate DOM ids), and there is
    // no stray third pair — so every `href="#tool-*-N"` resolves to one target.
    inspect(occurrences(html, "id=\"tool-call-1\""), content="1")
    inspect(occurrences(html, "id=\"tool-call-2\""), content="1")
    inspect(occurrences(html, "id=\"tool-result-1\""), content="1")
    inspect(occurrences(html, "id=\"tool-result-2\""), content="1")
    assert_false(html.contains("tool-call-3"))
    assert_false(html.contains("tool-result-3"))
  }
}

///|
test "empty, duplicate, and orphan ids get no pairing chip or anchor" {
  // A pairing chip must never link to a missing anchor, and no DOM id may be
  // emitted twice, so none of these unpairable ids may produce pairing markup.
  for mode in [@viz.RawLog, ModelView] {
    let html = render(@viz.render_session(unpairable_session(), mode))
    assert_false(html.contains("id=\"tool-call-"))
    assert_false(html.contains("id=\"tool-result-"))
    assert_false(html.contains("class=\"tool-link\""))
  }
}

///|
test "one call with two results is not paired in the raw view" {
  // Two results for id `d` make the result side ambiguous; the raw view shows
  // both, so it must not pair (which would need a single `tool-result-N` anchor).
  let raw = render(@viz.render_session(duplicate_result_session(), RawLog))
  assert_false(raw.contains("id=\"tool-call-"))
  assert_false(raw.contains("id=\"tool-result-"))
  assert_false(raw.contains("class=\"tool-link\""))
}

///|
test "a dangling call pairs only in the model view, where it is healed" {
  let session = dangling_call_session()
  // Raw has no result event for `only`, so nothing to pair.
  let raw = render(@viz.render_session(session, RawLog))
  assert_false(raw.contains("id=\"tool-call-"))
  assert_false(raw.contains("id=\"tool-result-"))
  // The model projection heals the dangling call with a synthetic result, giving
  // it a valid partner — so the call and its healed result cross-link here.
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("id=\"tool-call-1\""))
  assert_true(model.contains("id=\"tool-result-1\""))
  assert_true(model.contains("href=\"#tool-result-1\""))
  assert_true(model.contains("href=\"#tool-call-1\""))
}

///|
/// Plan-cadence reminders (the `[plan reminder]` prefix) get a dedicated card:
/// the checklist variant renders its steps as status-classed rows, the no-plan
/// variant keeps its prose, and an unrelated runtime notice keeps the generic
/// card. The reminder bodies mirror `plan_reminder_text` in `agent`.
test "plan reminder notices render a dedicated card with checklist rows" {
  let checklist_reminder =
    $|\{@agent_session.PlanReminderPrefix}
    $|The plan tool has not been called in a while. If progress was made,
    $|update step statuses; if the plan no longer matches the work,
    $|replace it or clear it with steps: []. Current plan:
    $|1. [completed] read the failing test
    $|2. [in_progress] fix the parser
    $|3. [pending] run moon test
  let no_plan_reminder =
    $|\{@agent_session.PlanReminderPrefix}
    $|The plan tool has not been used in this turn. If this task takes
    $|several distinct steps, record a plan with the plan tool and keep
    $|step statuses current. If not, ignore this reminder.
  let session = @agent_session.Session(SessionId("plan"), system_prompt="")
    .append(User(UserMessage("do a long task")))
    .append(Runtime(RuntimeNotice(checklist_reminder)))
    .append(Runtime(RuntimeNotice(no_plan_reminder)))
    .append(Runtime(RuntimeNotice("unrelated runtime context")))
  let html = render(@viz.render_session(session, RawLog))
  // Checklist variant: dedicated card, prose kept, one status-classed row per
  // step with a status icon before the numbered title, plus the shared
  // progress meter above the list.
  assert_true(html.contains("class=\"card runtime plan-reminder\""))
  assert_true(html.contains("Plan reminder"))
  assert_true(html.contains("Current plan:"))
  assert_true(html.contains("class=\"plan-steps\""))
  assert_true(html.contains("class=\"plan-step completed\""))
  assert_true(html.contains("class=\"plan-step in_progress\""))
  assert_true(html.contains("class=\"plan-step pending\""))
  assert_true(html.contains("step-icon"))
  assert_true(
    html.contains(
      "<span class=\"step-num\">2.</span><span class=\"step-title\">fix the parser</span>",
    ),
  )
  assert_true(html.contains("class=\"plan-progress\""))
  assert_true(html.contains("1/3"))
  // No-plan variant: the dedicated card without a checklist list.
  assert_true(html.contains("has not been used in this turn"))
  // Unrelated notices keep the generic runtime card.
  assert_true(html.contains("Runtime notice"))
  assert_true(html.contains("unrelated runtime context"))
}

///|
/// Two plan calls in sequence: the second completes one step, starts the next,
/// adds a new step, and silently drops one — exercising the dedicated plan
/// checklist plus every delta chip against the previous call's baseline.
fn plan_calls_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("plans"), system_prompt="")
  .append(User(UserMessage("build the feature")))
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(
          id="p1",
          name="plan",
          arguments="{\"steps\":[{\"title\":\"read the failing test\",\"status\":\"in_progress\"},{\"title\":\"fix the parser\",\"status\":\"pending\"},{\"title\":\"run moon test\",\"status\":\"pending\"}]}",
        ),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="p1",
        tool_name="plan",
        content="Plan updated: 0/3 done · in progress: read the failing test.",
      ),
    ),
  )
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(
          id="p2",
          name="plan",
          arguments="{\"steps\":[{\"title\":\"read the failing test\",\"status\":\"completed\"},{\"title\":\"fix the parser\",\"status\":\"in_progress\"},{\"title\":\"add a regression test\",\"status\":\"pending\"}]}",
        ),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="p2",
        tool_name="plan",
        content="Plan updated: 1/3 done · in progress: fix the parser.",
      ),
    ),
  )
  .append(Terminal(Finished("done")))
}

///|
/// `plan` tool calls get a dedicated rendering in both views: a status ribbon
/// on the folded summary line, and a progress meter plus status-classed
/// checklist instead of the generic key/value rows — with the raw JSON still
/// available for the Original toggle.
test "plan calls render a checklist with progress meter and status ribbon" {
  let html = render(@viz.render_session(plan_calls_session(), RawLog))
  // A plan card is the task's live state: it starts unfolded (`open`, written
  // after the attributes by the SSR), unlike every other tool call, which
  // stays folded until clicked.
  assert_true(
    html.contains("<details class=\"tool-call\" id=\"tool-call-1\" open>"),
  )
  assert_true(html.contains("class=\"tool-call-args-rendered plan-args\""))
  assert_true(html.contains("class=\"plan-ribbon\""))
  assert_true(html.contains("class=\"plan-ribbon-seg in_progress\""))
  assert_true(html.contains("class=\"plan-progress\""))
  assert_true(html.contains("0/3"))
  assert_true(html.contains("1/3"))
  assert_true(html.contains("class=\"plan-step completed\""))
  assert_true(html.contains("class=\"plan-step in_progress\""))
  assert_true(html.contains("class=\"plan-step pending\""))
  assert_true(html.contains("tool-call-args-original"))
  // The model view shares the same call rendering.
  let model = render(@viz.render_session(plan_calls_session(), ModelView))
  assert_true(model.contains("class=\"tool-call-args-rendered plan-args\""))
  assert_true(model.contains("class=\"plan-ribbon\""))
}

///|
/// A plan rewrite diffs against the previous plan call: completed/started/new
/// steps get delta chips, a dropped step stays visible as a ghost row, and the
/// baseline-less first call carries no chips at all.
test "a plan rewrite chips what changed and keeps dropped steps visible" {
  let html = render(@viz.render_session(plan_calls_session(), RawLog))
  assert_true(html.contains("step-delta-done"))
  assert_true(html.contains("step-delta-started"))
  assert_true(html.contains("step-delta-new"))
  assert_true(html.contains("step-delta-dropped"))
  assert_true(html.contains("class=\"plan-step dropped\""))
  // The dropped step's title survives in the second card's ghost row (plus its
  // own row in the first card).
  assert_true(occurrences(html, "run moon test") >= 2)
  // Only the second call diffs: done, started, new, dropped — four chips.
  assert_eq(occurrences(html, "step-delta step-delta-"), 4)
}

///|
/// A wholesale rewrite — fewer than half the steps carried over by title —
/// gets a single rewrite note instead of drowning the checklist in
/// "new"/"dropped" chips; reworded titles are indistinguishable from
/// replacements, so the diff backs off entirely.
test "a wholesale plan rewrite shows a note instead of per-step chips" {
  let html = two_plan_calls_raw(
    "{\"steps\":[{\"title\":\"old step one\",\"status\":\"in_progress\"},{\"title\":\"old step two\",\"status\":\"pending\"}]}",
    "{\"steps\":[{\"title\":\"reworded step one\",\"status\":\"in_progress\"},{\"title\":\"reworded step two\",\"status\":\"pending\"}]}",
  )
  assert_true(html.contains("plan-rewrite-note"))
  assert_false(html.contains("step-delta"))
  assert_false(html.contains("plan-step dropped"))
}

///|
/// A pure extension — every baseline step kept, new ones appended — is an
/// evolution, not a rewrite: carried steps chip their status changes and no
/// rewrite note appears even though fewer than half the NEW plan's steps
/// existed before.
test "extending a plan keeps delta chips instead of a rewrite note" {
  let before = "{\"steps\":[{\"title\":\"step a\",\"status\":\"in_progress\"}]}"
  let after = "{\"steps\":[{\"title\":\"step a\",\"status\":\"completed\"},{\"title\":\"step b\",\"status\":\"in_progress\"},{\"title\":\"step c\",\"status\":\"pending\"}]}"
  let html = two_plan_calls_raw(before, after)
  assert_false(html.contains("plan-rewrite-note"))
  assert_true(html.contains("step-delta-done"))
  assert_true(html.contains("step-delta-new"))
}

///|
/// Status regressions read honestly: a completed step coming back is
/// "reopened" (even to in_progress, which used to masquerade as "started"),
/// and an in_progress step set back to pending is "paused".
test "delta chips distinguish reopened and paused from started" {
  let before = "{\"steps\":[{\"title\":\"step a\",\"status\":\"completed\"},{\"title\":\"step b\",\"status\":\"in_progress\"}]}"
  let after = "{\"steps\":[{\"title\":\"step a\",\"status\":\"in_progress\"},{\"title\":\"step b\",\"status\":\"pending\"}]}"
  let html = two_plan_calls_raw(before, after)
  assert_true(html.contains("step-delta-reopened"))
  assert_true(html.contains("step-delta-paused"))
  assert_false(html.contains("step-delta-started"))
}

///|
/// A plan call the tool rejected never changed the recorded plan, so it
/// neither diffs against the plan before it nor becomes the baseline for the
/// plan after it — the successful calls diff across it as if it were absent.
test "a tool-rejected plan call is not a diff baseline" {
  let plan_a = "{\"steps\":[{\"title\":\"step a\",\"status\":\"in_progress\"}]}"
  // Well-formed for the lenient viewer decoder, but rejected by the tool
  // (two in_progress steps) — recorded with an errored result.
  let rejected = "{\"steps\":[{\"title\":\"step a\",\"status\":\"in_progress\"},{\"title\":\"phantom step\",\"status\":\"in_progress\"}]}"
  let plan_c = "{\"steps\":[{\"title\":\"step a\",\"status\":\"completed\"}]}"
  let session = @agent_session.Session(SessionId("reject"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="p1", name="plan", arguments=plan_a),
        ]),
      ),
    )
    .append(Tool(ToolResult(tool_call_id="p1", tool_name="plan", content="ok")))
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="p2", name="plan", arguments=rejected),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="p2",
          tool_name="plan",
          content="error: at most one in_progress step",
          is_error=true,
        ),
      ),
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="p3", name="plan", arguments=plan_c),
        ]),
      ),
    )
    .append(Tool(ToolResult(tool_call_id="p3", tool_name="plan", content="ok")))
  let html = render(@viz.render_session(session, RawLog))
  // p3 diffs against p1 (step a: in_progress -> completed), not against the
  // rejected p2 — no ghost row for the phantom step it tried to introduce.
  assert_true(html.contains("step-delta-done"))
  assert_false(html.contains("plan-step dropped"))
  assert_false(html.contains("step-delta-dropped"))
}

///|
/// Plan calls whose ids are empty or duplicated cannot be keyed to a
/// baseline (mirroring `assign_pair_tags`), so their cards render the
/// checklist without delta chips instead of diffing against the wrong call.
test "duplicate and empty plan-call ids render without delta chips" {
  let plan_a = "{\"steps\":[{\"title\":\"step a\",\"status\":\"in_progress\"}]}"
  let plan_b = "{\"steps\":[{\"title\":\"step a\",\"status\":\"completed\"}]}"
  let session = @agent_session.Session(SessionId("dupids"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="dup", name="plan", arguments=plan_a),
        ]),
      ),
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="dup", name="plan", arguments=plan_b),
        ]),
      ),
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="", name="plan", arguments=plan_b),
        ]),
      ),
    )
  let html = render(@viz.render_session(session, RawLog))
  assert_true(html.contains("plan-args"))
  assert_false(html.contains("step-delta"))
}

///|
/// Goal set/cleared/blocked markers — parsed by the shared
/// `@agent_session.goal_marker` decoder — get dedicated cards with the goal
/// text (or reason) as the payload instead of a generic runtime notice.
test "goal markers render dedicated set, cleared, and blocked cards" {
  let session = @agent_session.Session(SessionId("goal"), system_prompt="")
    .append(
      Runtime(
        RuntimeNotice(
          "\{@agent_session.GoalPrefix}\nShip the parser rewrite\nwith tests passing",
        ),
      ),
    )
    .append(
      Runtime(
        RuntimeNotice(
          "\{@agent_session.GoalBlockedPrefix}\nupstream API is down",
        ),
      ),
    )
    .append(Runtime(RuntimeNotice(@agent_session.GoalClearedNotice)))
  let html = render(@viz.render_session(session, RawLog))
  assert_true(html.contains("class=\"card runtime goal-set\""))
  assert_true(html.contains("Goal set"))
  assert_true(html.contains("class=\"goal-text\""))
  // Multi-line goal text survives inside the marked block.
  assert_true(html.contains("Ship the parser rewrite\nwith tests passing"))
  assert_true(html.contains("class=\"card runtime goal-blocked\""))
  assert_true(html.contains("upstream API is down"))
  assert_true(html.contains("class=\"card runtime goal-cleared\""))
  assert_true(html.contains("standing goal cleared"))
}

///|
/// Goal reminders and finish-time goal checks surface the goal text as the
/// card's payload and fold the fixed assessment boilerplate away; a notice
/// whose shape is not recognized keeps its verbatim text. The bodies mirror
/// `goal_reminder_text` / `goal_check_text` in `agent`.
test "goal reminders and checks show the goal and fold the boilerplate" {
  let reminder =
    $|\{@agent_session.GoalReminderPrefix}
    $|The standing goal for this session:
    $|Ship the parser rewrite with tests passing
    $|Assess it briefly at this turn boundary:
    $|- Fully met? Verify per the goal's own criteria first, then
    $|  record that by calling the goal tool with status "met", then finish.
    $|- Otherwise continue working toward it.
  let check =
    $|\{@agent_session.GoalCheckPrefix}
    $|The standing goal for this session:
    $|Ship the parser rewrite with tests passing
    $|You attempted to finish. If the goal is fully met, record that by
    $|calling the goal tool with status "met", then finish.
  let odd =
    $|\{@agent_session.GoalReminderPrefix}
    $|some future body this build does not know
  let session = @agent_session.Session(SessionId("remind"), system_prompt="")
    .append(Runtime(RuntimeNotice(reminder)))
    .append(Runtime(RuntimeNotice(check)))
    .append(Runtime(RuntimeNotice(odd)))
  let html = render(@viz.render_session(session, RawLog))
  assert_true(html.contains("class=\"card runtime goal-reminder\""))
  assert_true(html.contains("Goal reminder"))
  assert_true(html.contains("class=\"card runtime goal-check\""))
  assert_true(html.contains("Goal check"))
  // Both recognized notices surface the goal in the marked block and keep
  // the verbatim notice one fold away.
  assert_eq(occurrences(html, "class=\"goal-text\""), 2)
  assert_eq(occurrences(html, "class=\"goal-boilerplate\""), 2)
  assert_true(html.contains("Ship the parser rewrite with tests passing"))
  // The unrecognized shape falls back to verbatim text, no goal block.
  assert_true(html.contains("some future body this build does not know"))
}

///|
/// The goal is arbitrary user input: a goal line that looks like the OTHER
/// notice's delimiter — or like this notice's own — must not truncate the
/// marked payload. Only the notice kind's delimiter counts, and its last
/// occurrence wins.
test "delimiter-looking goal lines are not mistaken for boilerplate" {
  let reminder =
    $|\{@agent_session.GoalReminderPrefix}
    $|The standing goal for this session:
    $|Review the migration
    $|You attempted to finish the old path; now recover it
    $|Assess it briefly at this turn boundary: for each module
    $|Assess it briefly at this turn boundary:
    $|- Fully met? Verify per the goal's own criteria first, then finish.
  let session = @agent_session.Session(SessionId("tricky"), system_prompt="").append(
    Runtime(RuntimeNotice(reminder)),
  )
  let html = render(@viz.render_session(session, RawLog))
  // The full three-line goal survives in the marked block: the check
  // sentinel inside it is goal text (wrong notice kind), and the goal's own
  // delimiter-prefixed line loses to the LAST (real) delimiter.
  assert_true(
    html.contains(
      (
        #|Review the migration
        #|You attempted to finish the old path; now recover it
        #|Assess it briefly at this turn boundary: for each module
      ),
    ),
  )
}

///|
/// The reminder meter parses each line's leading status bracket, so a title
/// that mentions "[completed]" is not miscounted, and an unknown status word
/// renders literally instead of being disguised as a pending ring.
test "reminder meter parses statuses and unknown statuses stay visible" {
  let reminder =
    $|\{@agent_session.PlanReminderPrefix}
    $|Current plan:
    $|1. [pending] mark [completed] items in the tracker
    $|2. [blocked] wait for CI
  let session = @agent_session.Session(SessionId("odd"), system_prompt="").append(
    Runtime(RuntimeNotice(reminder)),
  )
  let html = render(@viz.render_session(session, RawLog))
  // Nothing is completed: the meter must say 0/2 despite the title text.
  assert_true(html.contains("0/2"))
  // The unknown status renders as its literal word, not a pending icon.
  assert_true(html.contains("<span class=\"step-status\">blocked</span>"))
}

///|
/// A cleared plan (`steps: []`) renders an explicit marker rather than an
/// empty checklist, and malformed plan arguments keep the generic rendering —
/// the viewer never guesses at a plan the tool would have rejected.
test "cleared and malformed plans degrade gracefully" {
  let cleared_html = render_tool_call("plan", "{\"steps\":[]}")
  assert_true(cleared_html.contains("plan cleared"))
  assert_false(cleared_html.contains("plan-ribbon"))
  assert_false(cleared_html.contains("plan-progress"))
  let malformed_html = render_tool_call(
    "plan", "{\"steps\":[{\"title\":\"x\",\"status\":\"doing\"}]}",
  )
  assert_false(malformed_html.contains("plan-args"))
  assert_true(malformed_html.contains("class=\"arg-key\""))
}

///|
/// Every raw-view card anchors at its durable sequence (`seq-N`), the ids the
/// scrollspy, refresh restore, and step scrubber navigate by. A paired tool
/// result keeps its pair anchor (the call↔result cross-link targets it);
/// unpaired results fall back to the sequence anchor.
test "raw cards carry stable seq anchors" {
  let html = render(@viz.render_session(multi_step_session(), RawLog))
  assert_true(html.contains("id=\"seq-1\"")) // user
  assert_true(html.contains("id=\"seq-2\"")) // assistant
  assert_true(html.contains("id=\"seq-4\"")) // final assistant
  // The tool result at seq 3 is paired: pair anchor wins, no seq id.
  assert_true(html.contains("id=\"tool-result-1\""))
  assert_false(html.contains("id=\"seq-3\""))
  // An unpaired (orphan) result anchors at its sequence instead.
  let orphan = render(@viz.render_session(unpairable_session(), RawLog))
  assert_true(orphan.contains("id=\"seq-2\""))
}

///|
/// Model-view cards anchor at the sequence of the event backing them; the
/// system prompt and synthetic repair messages have no durable event, so
/// they carry no seq anchor.
test "model cards anchor event-backed messages only" {
  let html = render(@viz.render_session(multi_step_session(), ModelView))
  assert_true(html.contains("id=\"seq-1\""))
  assert_true(html.contains("id=\"seq-2\""))
  assert_true(html.contains("id=\"seq-4\"")) // final assistant
  // The healed synthetic result of a dangling call gets no seq anchor (it
  // pairs, so it carries the pair id instead).
  let healed = render(@viz.render_session(dangling_call_session(), ModelView))
  assert_true(healed.contains("id=\"tool-result-1\""))
}

///|
/// The step scrubber renders one `data-seq` segment per agent step, tints
/// segments whose range contains a failed tool result, and disappears for
/// sessions with fewer than two steps.
test "step scrubber marks steps and their failures" {
  // Two steps: the assistant at seq 2 (whose shell call fails at seq 3) and
  // the assistant at seq 4. The terminal right after an assistant message is
  // that step's own answer, not a new step.
  let session = @agent_session.Session(SessionId("scrub"), system_prompt="")
    .append(User(UserMessage("go")))
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"boom\"}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="shell",
          content="exit 1",
          is_error=true,
        ),
      ),
    )
    .append(Assistant(AssistantMessage("recovered")))
    .append(Terminal(Finished("done")))
  let html = render(@viz.step_scrubber(session))
  assert_true(html.contains("class=\"step-scrubber\""))
  assert_eq(occurrences(html, "data-seq="), 2)
  assert_true(html.contains("data-seq=\"2\""))
  assert_true(html.contains("data-seq=\"4\""))
  // Hover labels ride data-label (instant shell tooltip, not native title);
  // the failing step's label names the failure.
  assert_true(html.contains("data-label=\"Step 1/2 · has failures\""))
  assert_true(html.contains("data-label=\"Step 2/2\""))
  assert_false(html.contains("title="))
  // Only the first step's range contains the failed result.
  assert_eq(occurrences(html, "step-seg has-error"), 1)
  // A one-step session has nothing to scrub.
  let single = render(@viz.step_scrubber(error_tool_session()))
  assert_false(single.contains("step-scrubber"))
}

///|
/// Stamped events render relative offsets and a turn duration; unstamped
/// events (the 0 sentinel) render no time chips at all.
test "raw view shows total-second offsets and turn duration from ts" {
  let stamped = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(User(UserMessage("go")), unix_ms=1781151318110L)
    .append(Runtime(RuntimeNotice("working")), unix_ms=1781151319242L)
    .append(Terminal(Finished("done")), unix_ms=1781151443650L)
  let html = render(@viz.render_session(stamped, RawLog))
  assert_true(html.contains("+0.0s"))
  assert_true(html.contains("+1.1s"))
  assert_true(html.contains("+125.5s"))
  assert_true(html.contains("· 125.5s"))
  assert_false(html.contains("+2m 05.5s"))
  let unstamped = @agent_session.Session(SessionId("u"), system_prompt="")
    .append(User(UserMessage("go")))
    .append(Terminal(Finished("done")))
  let plain = render(@viz.render_session(unstamped, RawLog))
  assert_false(plain.contains("card-ts"))
}

///|
/// A parent session holding one explore call/result pair whose brief names
/// sub-run sr-2 — the stamp the explore tool writes on its results.
fn subrun_sample_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("run"), system_prompt="sys")
  .append(User(UserMessage("find the API")))
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(id="c1", name="explore", arguments="{\"query\": \"how\"}"),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="c1",
        tool_name="explore",
        content="Answer: like this.",
        brief="explore sr-2 (1 citation(s), 7 step(s))",
      ),
    ),
  )
  .append(Terminal(Finished("done")))
}

///|
test "a subrun result links its child session and nests a loaded transcript" {
  let session = subrun_sample_session()
  // Chip in both views: the href targets the child session id derived from
  // the parent id plus the brief's sr-N stamp.
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("subrun-link"))
  assert_true(raw.contains("href=\"#s=run-sr-2\""))
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("href=\"#s=run-sr-2\""))
  // No child loaded: chip only, no nested transcript.
  assert_false(raw.contains("subrun-transcript"))
  // With the child supplied, the raw view nests its transcript; the model
  // view stays chip-only (the child's turn is nothing the model was fed).
  let child = @agent_session.Session(
      SessionId("run-sr-2"),
      system_prompt="scout",
    )
    .append(User(UserMessage("q")))
    .append(Assistant(AssistantMessage("looking")))
    .append(Terminal(Finished("submitted")))
  let children : Map[String, @agent_session.Session] = Map([])
  children.set("run-sr-2", child)
  let nested = render(
    @viz.render_session(session, RawLog, subrun_children=children),
  )
  assert_true(nested.contains("subrun-transcript"))
  assert_true(nested.contains("Subagent transcript · run-sr-2"))
  assert_false(
    render(@viz.render_session(session, ModelView, subrun_children=children)).contains(
      "subrun-transcript",
    ),
  )
  // An ordinary tool result never grows a chip.
  assert_false(
    render(@viz.render_session(clean_sample_session(), RawLog)).contains(
      "subrun-link",
    ),
  )
  // The prefetch scanner surfaces the same reference.
  assert_eq(@viz.subrun_child_ids(session, "run"), ["run-sr-2"])
}

///|
test "nested transcripts namespace their anchors; chip hrefs are encoded" {
  let session = subrun_sample_session()
  let child = @agent_session.Session(
      SessionId("run-sr-2"),
      system_prompt="scout",
    )
    .append(User(UserMessage("q")))
    .append(Terminal(Finished("submitted")))
  let children : Map[String, @agent_session.Session] = Map([])
  children.set("run-sr-2", child)
  let nested = render(
    @viz.render_session(session, RawLog, subrun_children=children),
  )
  // The child's cards anchor under its own namespace; the parent document
  // keeps exactly one bare seq-1 (K3 review: duplicate DOM ids).
  assert_true(nested.contains("id=\"run-sr-2--seq-1\""))
  let bare = nested.split("id=\"seq-1\"").count() - 1
  assert_eq(bare, 1)
  // After the nested render, top-level anchors are back to bare form.
  let again = render(@viz.render_session(session, RawLog))
  assert_true(again.contains("id=\"seq-1\""))
  assert_false(again.contains("--seq-"))
  // A parent id outside the unreserved set is percent-encoded in the chip
  // href (URLSearchParams would corrupt a raw '+', '&', or space).
  let odd = @agent_session.Session(SessionId("a+b c"), system_prompt="").append(
    Tool(
      ToolResult(
        tool_call_id="c9",
        tool_name="explore",
        content="ok",
        brief="explore sr-4 (0 citation(s), 3 step(s))",
      ),
    ),
  )
  let html = render(@viz.render_session(odd, RawLog))
  assert_true(html.contains("href=\"#s=a%2Bb%20c-sr-4\""))
}

///|
/// One real escalated call plus lookalikes that must not enter the filter:
/// `false`, a string value, a nested value, and malformed JSON.
fn escalated_tool_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("escalated"), system_prompt="")
  .append(User(UserMessage("run it")))
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(
          id="yes",
          name="shell",
          arguments="{\"cmd\":\"make\",\"escalated\":true}",
        ),
        ToolCall(
          id="no",
          name="shell",
          arguments="{\"cmd\":\"make\",\"escalated\":false}",
        ),
        ToolCall(
          id="string",
          name="shell",
          arguments="{\"escalated\":\"true\"}",
        ),
        ToolCall(
          id="nested",
          name="shell",
          arguments="{\"options\":{\"escalated\":true}}",
        ),
        ToolCall(id="malformed", name="shell", arguments="{\"escalated\":true"),
      ]),
    ),
  )
  .append(
    Tool(ToolResult(tool_call_id="yes", tool_name="shell", content="built")),
  )
  .append(
    Tool(ToolResult(tool_call_id="no", tool_name="shell", content="built")),
  )
  .append(Terminal(Finished("done")))
}

///|
test "escalated tool calls and their results are tagged in both views" {
  let session = escalated_tool_session()
  for mode in [@viz.RawLog, ModelView] {
    let html = render(@viz.render_session(session, mode))
    assert_eq(occurrences(html, "tool-call-escalated"), 1)
    assert_eq(occurrences(html, "card tool escalated"), 1)
    assert_eq(@viz.rendered_escalated_count(session, mode), 1)
  }
}
