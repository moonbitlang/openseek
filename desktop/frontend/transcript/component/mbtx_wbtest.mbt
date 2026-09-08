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
