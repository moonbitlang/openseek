///|
test "an mbtx call decodes to its program and its arguments" {
  let arguments =
    #|{"source":"fn main {\n  println(\"hi\")\n}","target":"js","cwd":"sub/dir"}
  guard decode_mbtx_call(arguments) is Some(call) else {
    fail("expected a readable mbtx call")
  }
  assert_eq(
    call.source,
    (
      #|fn main {
      #|  println("hi")
      #|}
    ),
  )
  assert_eq(call.chips, ["target: js", "cwd: sub/dir"])
}

///|
/// The chip row is built from a fixed key order rather than the recorded
/// JSON's, which is whatever the model emitted and is not preserved by the
/// parsed map — otherwise two identical calls could chip in different orders.
test "mbtx chips keep fixed order and render the historical background flag" {
  let arguments =
    #|{"zzz":1,"run_in_background":true,"cwd":null,"source":"fn main {  }","warning":"on","target":"wasm","aaa":"x","extra":{"k":1}}
  guard decode_mbtx_call(arguments) is Some(call) else {
    fail("expected a readable mbtx call")
  }
  // A null is the tool's own spelling of "unset", and a nested value cannot be
  // stated in one line: neither gets a chip, and the Original JSON view is
  // what carries them. `run_in_background` is no longer accepted by the live
  // tool, but must remain visible in already-recorded transcripts.
  assert_eq(call.chips, [
    "target: wasm", "warning: on", "run_in_background: true", "aaa: x", "zzz: 1",
  ])
}

///|
test "an mbtx chip clamps one oversized argument" {
  let arguments = "{\"source\":\"fn main {  }\",\"cwd\":\"\{"d/".repeat(200)}\"}"
  guard decode_mbtx_call(arguments) is Some(call) else {
    fail("expected a readable mbtx call")
  }
  assert_eq(call.chips.length(), 1)
  assert_true(call.chips[0].has_suffix("…"))
  assert_true(call.chips[0].length() < 140)
}

///|
/// The card renders the whole program without `truncate_output`: a program
/// past that helper's 101-line clamp still shows every line under its true
/// number, with no skip marker — reintroducing the clamp would misnumber the
/// tail against the result's `line:column` diagnostics.
#warnings("-alert_unstable")
test "an mbtx program past the transcript clamp keeps every numbered line" {
  let lines : Array[String] = []
  for index in 0..<120 {
    lines.push("let x\{index} = \{index}")
  }
  let arguments : Json = { "source": lines.join("\n"), "target": "js" }
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="mbtx",
      arguments=Some(arguments.stringify()),
      has_result=true,
      is_error=false,
      brief=Some("mbtx (exit=0)"),
    ),
    content: "ok",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("<span class=\"moonbit-gutter\">120</span>"))
  assert_false(markup.contains("skipped"))
}

///|
/// A failed mbtx row names its stage from the brief alone — build errors are
/// fixed in the source, runtime errors in the program's behavior, and the row
/// says which before the card is opened. A brief carrying neither shape (a
/// timeout, a kill) keeps the generic word, as does every other tool.
#warnings("-alert_unstable")
test "a failed mbtx row names its failure stage" {
  fn markup_for(brief : String, is_error : Bool) -> String {
    let rendered = tool_call_view({
      kind: Tool(
        call_id="c1",
        name="mbtx",
        arguments=Some("{\"source\":\"fn main {  }\"}"),
        has_result=true,
        is_error~,
        brief=Some(brief),
      ),
      content: "x",
      ts: None,
      sequence: None,
    })
    @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  }

  let build = markup_for("mbtx (build failed, exit=1)", true)
  assert_true(build.contains("tool-stage-build"))
  assert_true(build.contains("build error"))
  assert_false(build.contains(">failed<"))
  // Every build-phase brief shape maps to the same stage word.
  assert_true(markup_for("mbtx (build timeout)", true).contains("build error"))
  let runtime = markup_for("mbtx (exit=1)", true)
  assert_true(runtime.contains("tool-stage-run"))
  assert_true(runtime.contains("runtime error"))
  // A clean exit carries no marker at all.
  let ok = markup_for("mbtx (exit=0)", false)
  assert_false(ok.contains("runtime error"))
  assert_false(ok.contains(">failed<"))
  // A brief outside both stage shapes keeps the generic word.
  assert_true(markup_for("mbtx (timeout)", true).contains(">failed<"))
}

///|
/// A payload this card cannot read keeps the generic arguments rendering,
/// which clamps before parsing — nothing is ever shown as a program that is
/// not one.
test "an unreadable mbtx payload decodes to nothing" {
  assert_true(decode_mbtx_call("not json") is None)
  assert_true(decode_mbtx_call("[1, 2]") is None)
  assert_true(decode_mbtx_call("{\"target\":\"js\"}") is None)
  assert_true(decode_mbtx_call("{\"source\":42}") is None)
  assert_true(decode_mbtx_call("{\"source\":\"  \\n \"}") is None)
  let oversized = "{\"source\":\"\{"x".repeat(200_000)}\"}"
  assert_true(decode_mbtx_call(oversized) is None)
}

///|
#warnings("-alert_unstable")
test "a failed mbtx row still reads as a program, not escaped JSON" {
  let arguments =
    #|{"source":"fn main {\n  println(1 / 0)\n}","target":"js"}
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="mbtx",
      arguments=Some(arguments),
      has_result=true,
      // For this tool an error is a run that failed, which is exactly when its
      // source matters — the card is not gated on the result the way `plan`'s
      // is, where an error means the arguments were refused.
      is_error=true,
      brief=Some("mbtx (exit=1)"),
    ),
    content: "boom",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("moonbit-source"))
  assert_true(markup.contains("language-moonbit"))
  assert_true(markup.contains("<span class=\"mtk3\">fn</span>"))
  assert_true(markup.contains("<span class=\"mtk6\">1</span>"))
  // Each source line carries its number, for matching the result's
  // `line:column` compiler diagnostics against the program.
  assert_true(markup.contains("<span class=\"moonbit-gutter\">1</span>"))
  assert_true(markup.contains("<span class=\"moonbit-gutter\">3</span>"))
  assert_true(markup.contains("tool-card-chip"))
  assert_true(markup.contains("target: js"))
  // The program reads as lines rather than as one JSON-escaped string.
  assert_true(markup.contains("println(1 / 0)"))
  // Program and the exact payload share the request's tab set. Output stays in
  // the distinct result row, matching the viz HTML render.
  assert_true(markup.contains("class=\"tool-call-tabs\""))
  assert_eq(markup.split("class=\"tool-call-tab-input\"").length(), 3)
  assert_true(markup.contains(">Program</label>"))
  assert_true(markup.contains(">Original JSON</label>"))
  assert_false(markup.contains(">Output</label>"))
  // The payload as the model sent it stays available in its own tab.
  assert_true(markup.contains("Original JSON"))
  assert_true(markup.contains("\\n"))
  // The run's own output stays present in the result row.
  assert_true(markup.contains("boom"))
  assert_true(markup.contains("tool-call-section-label\">Output"))
  assert_true(markup.contains("class=\"tool-result error\""))
}

///|
#warnings("-alert_unstable")
test "another tool's arguments keep the generic JSON rendering" {
  let arguments =
    #|{"source":"fn main {  }"}
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="write",
      arguments=Some(arguments),
      has_result=true,
      is_error=false,
      brief=Some("wrote a file"),
    ),
    content: "",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_false(markup.contains("moonbit-source"))
  assert_true(markup.contains("tool-call-arguments"))
}
