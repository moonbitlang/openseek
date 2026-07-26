///|
/// The exhaustive line-level pins for the private denial-classification engine.
/// Keeping these white-box lets the public API expose only a prepared
/// `SandboxedCommand`, while this platform-independent behavior remains fully
/// covered without requiring a live sandbox.
fn reports(subjects : Array[String], text : String) -> Bool {
  source_write_denied_in_text(text, subjects)
}

///|
test "source-write denial detection in command output" {
  // run_moonbit's shape: a MoonBit runtime error for a denied source write.
  assert_true(
    reports(
      [],
      "OSError(\"@fs.open(): \\\"keep.mbt\\\": Operation not permitted\")",
    ),
  )
  assert_true(reports([], "sh: main.mbt: Operation not permitted\n"))
  assert_true(reports([], "sh: moon.work: Operation not permitted\n"))
  // Generic denials and prose mentions are not source-write denials.
  assert_false(reports([], "Permission denied\n"))
  assert_false(reports([], "Permission denied while reading main.mbt\n"))
  assert_false(reports([], "Permission denied while reading 'main.mbt'\n"))
  // The subject may follow the denial (python's errno shape, plain colon).
  assert_true(
    reports(
      [],
      "PermissionError: [Errno 1] Operation not permitted: 'main.mbt'\n",
    ),
  )
  assert_true(reports([], "Operation not permitted: main.mbt\n"))
  assert_true(reports([], "Permission denied: main.mbt\n"))
  // A denied directory is recognized only as a known denial subject.
  let dir_rename = "PermissionError: [Errno 1] Operation not permitted: 'pkg'\n"
  assert_false(reports([], dir_rename))
  assert_true(reports(["pkg"], dir_rename))
  assert_false(reports([], "foo: Operation not permitted\n"))
  assert_false(reports(["pkg"], "foo: Operation not permitted\n"))
  // A source path without any denial wording is not a denial either.
  assert_false(reports([], "compiled keep.mbt: ok"))
}
