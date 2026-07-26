///|
/// The denial scan runs after the run's deadline has expired, so its work must
/// stay bounded however hard a snippet flooded: an over-budget log is scanned
/// at its head and tail only. With a tiny test budget, a denial in either
/// scanned region is found; one buried in the skipped middle is (by design)
/// not; a log within budget is scanned whole.
async test "denial scan is bounded to the log's head and tail" {
  @vfs.with_tmpdir(prefix="run-moonbit-denial-scan-", dir => {
    let denial = "sh: main.mbt: Operation not permitted\n"
    let filler_line = "\{String::make(63, 'x')}\n"
    fn filler(lines : Int) -> String {
      let out = StringBuilder()
      for _ in 0..<lines {
        out.write_string(filler_line)
      }
      out.to_string()
    }

    async fn scan(name : String, content : String) -> Bool {
      let path = "\{dir}/\{name}.log"
      @fs.write_file(path, content, create_mode=CreateOrTruncate)
      log_shows_source_write_denial(
        path,
        text => text.contains("main.mbt: Operation not permitted"),
        budget_bytes=1024,
      )
    }

    // within budget (<= 2KB): scanned whole, wherever the denial sits
    assert_true(scan("small", filler(10) + denial + filler(10)))
    // over budget: the head region sees a leading denial
    assert_true(scan("head", denial + filler(64)))
    // over budget: the tail region sees a trailing denial
    assert_true(scan("tail", filler(64) + denial))
    // over budget with the denial only in the skipped middle: missed by design
    assert_false(scan("middle", filler(20) + denial + filler(20)))
    // no denial at all
    assert_false(scan("clean", filler(64)))
  })
}

///|
/// The warn-off spec must come from the toolchain's own table: moonc rejects
/// ids beyond its maximum, so a hardcoded ceiling breaks every default run on
/// an older toolchain (the desktop runtime pins one), and a too-low ceiling
/// leaks newer warnings. The parser disables 1..max by ranges skipping the
/// error-state ids, and yields "" (no flag at all) when nothing parses.
test "warn-off spec derivation from the toolchain warning table" {
  let help =
    #|Available warnings:
    #|mnemonic                   description                 id state
    #|unused_value               Unused variable.             2 warn
    #|partial_match              Partial pattern matching.   11 error
    #|unused_mut                 Unused mutability.          15 error
    #|deprecated                 Deprecated API usage.       20 warn
    #|unused_default_value       Default value never used.   32 off
    #|multiline_string_escape    Deprecated escape.          40 error
    #|invalid_inline_wasm        Invalid inline-wasm.        44 error
    #|unannotated_ffi            Unannotated FFI param type  55 error
    #|type_param_method          Deprecated call.            83 warn
    #|A                          all warnings
    #|state: warn = enabled, error = promoted to error, off = disabled
  assert_eq(
    parse_warn_off_list(help),
    "-1..10-12..14-16..39-41..43-45..54-56..83",
  )
  // no parsable table → no flag at all (fail-open to visible warnings)
  assert_eq(parse_warn_off_list(""), "")
  assert_eq(parse_warn_off_list("mnemonic id state\nnothing here"), "")
  // error ids at the edges produce no empty or inverted ranges
  assert_eq(parse_warn_off_list("a x 1 error\nb y 2 warn\nc z 3 error"), "-2")
  // a lone single-id gap renders as "-n", not a degenerate range
  assert_eq(parse_warn_off_list("a x 2 error\nb y 3 warn"), "-1-3")
  // CRLF output (Windows toolchains) parses identically
  assert_eq(parse_warn_off_list("a x 2 error\r\nb y 3 warn\r\n"), "-1-3")
}
