///|
/// Shells provide controlled child-process fixtures only; compiler checks pass
/// their executable and argument array directly to collect_process_output.
#cfg(not(platform="windows"))
fn output_fixture(unix : String, windows : String) -> (String, Array[String]) {
  ignore(windows)
  ("sh", ["-c", unix])
}

///|
#cfg(platform="windows")
fn output_fixture(unix : String, windows : String) -> (String, Array[String]) {
  ignore(unix)
  (
    "powershell.exe",
    [
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;" + windows,
    ],
  )
}

///|
async test "compiler capture merges streams and retains a non-zero exit code" {
  let (program, args) = output_fixture(
    "printf out; printf err >&2; exit 7", "[Console]::Out.Write('out'); [Console]::Error.Write('err'); exit 7",
  )
  let output = collect_process_output(
    program,
    args,
    cwd=".",
    max_output_chars=100,
  )
  assert_eq(output.exit_code, Some(7))
  assert_eq(output.text, "outerr")
  assert_false(output.output_limit_reached)
}

///|
async test "compiler capture preserves Unicode at the exact character limit" {
  let (program, args) = output_fixture(
    "printf '中😀'", "[Console]::Out.Write('中😀')",
  )
  let output = collect_process_output(
    program,
    args,
    cwd=".",
    max_output_chars=2,
  )
  assert_eq(output.exit_code, Some(0))
  assert_eq(output.text, "中😀")
  assert_false(output.output_limit_reached)
}

///|
async test "compiler capture truncates on characters and stops a live producer" {
  let (program, args) = output_fixture(
    "printf '中😀x'; exec sleep 30", "[Console]::Out.Write('中😀x'); Start-Sleep -Seconds 30",
  )
  let result = @async.with_timeout_opt(10000, () => {
    collect_process_output(program, args, cwd=".", max_output_chars=2)
  })
  guard result is Some(output) else {
    fail("output limit did not stop capture")
  }
  assert_eq(output.exit_code, None)
  assert_eq(output.text, "中😀")
  assert_true(output.output_limit_reached)
}

///|
async test "compiler capture gives children immediate stdin EOF" {
  let (program, args) = output_fixture(
    "if read line; then exit 1; fi; printf eof", "if ([Console]::In.ReadToEnd().Length -ne 0) { exit 1 }; [Console]::Out.Write('eof')",
  )
  let result = @async.with_timeout_opt(10000, () => {
    collect_process_output(program, args, cwd=".", max_output_chars=100)
  })
  guard result is Some(output) else { fail("child did not receive stdin EOF") }
  assert_eq(output.exit_code, Some(0))
  assert_eq(output.text, "eof")
  assert_false(output.output_limit_reached)
}

///|
#cfg(not(platform="windows"))
async test "compiler capture preserves literal arguments and the working directory" {
  let dir = @fs.tmpdir(prefix="openseek-process-output-")
  @fs.write_file("\{dir}/marker", "cwd-ok", create_mode=CreateOrTruncate)
  let literal = "space ; $HOME $(echo expanded) ' quote"
  let output = collect_process_output(
    "sh",
    ["-c", "printf '%s' \"$1\"; cat marker", "fixture", literal],
    cwd=dir,
    max_output_chars=100,
  )
  @fs.rmdir(dir, recursive=true)
  assert_eq(output.exit_code, Some(0))
  assert_eq(output.text, literal + "cwd-ok")
  assert_false(output.output_limit_reached)
}

///|
/// Reads cut the stream wherever they fall, so a character's bytes arrive in
/// two pieces: the capture must reassemble them, and count characters the
/// same whichever way the stream was cut.
async test "compiler capture reassembles characters split across reads" {
  let (program, args) = output_fixture(
    "yes '中😀' | head -n 2000 | tr -d '\\n'", "[Console]::Out.Write('中😀' * 2000)",
  )
  let whole = collect_process_output(
    program,
    args,
    cwd=".",
    max_output_chars=4000,
  )
  assert_false(whole.output_limit_reached)
  assert_true(whole.text == "中😀".repeat(2000))
  let cut = collect_process_output(
    program,
    args,
    cwd=".",
    max_output_chars=3001,
  )
  assert_true(cut.output_limit_reached)
  assert_true(cut.text == "中😀".repeat(1500) + "中")
}

///|
test "decoding holds back the bytes of an incomplete character" {
  let bytes = @utf8.encode("a中😀")
  assert_eq(decode_complete_chars(bytes), ("a中😀", b""))
  // One byte short of the emoji: its first three bytes wait for the rest.
  let (text, rest) = decode_complete_chars(
    bytes[:bytes.length() - 1].to_owned(),
  )
  assert_eq(text, "a中")
  assert_eq(rest.length(), 3)
  assert_eq(
    decode_complete_chars(rest + bytes[bytes.length() - 1:].to_owned()),
    ("😀", b""),
  )
  // Malformed bytes are decoded lossily, with nothing held back.
  assert_eq(
    decode_complete_chars(b"a\xffb\xffcd"),
    ("a\u{fffd}b\u{fffd}cd", b""),
  )
  // A character split after malformed bytes is still held back and
  // completed by the next read, not replaced.
  let (text, rest) = decode_complete_chars(b"\xffabcd\xe4\xb8")
  assert_eq(text, "\u{fffd}abcd")
  assert_eq(decode_complete_chars(rest + b"\xadzab"), ("中zab", b""))
  // Three continuation bytes end a four-byte character: nothing to wait for.
  assert_eq(incomplete_tail_length(@utf8.encode("😀")), 0)
  assert_eq(incomplete_tail_length(b""), 0)
}
