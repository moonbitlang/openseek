///|
test "display polls equal full ordered replacement at every split" {
  let input = "头aba🌙-ababa\r\n尾aa"
  let chunks = input.to_array()
  for
    rules in [
      [("aba", "X"), ("X🌙", "longer"), ("longer-", ""), ("aa", "尾")],
      [("", "."), (".头.", "start"), ("a", ""), ("", "🌙")],
    ] {
    for n in [1, 6, 12, 30] {
      let view = DisplayTail::new(rules, n)
      let mut prefix = ""
      for end in 0..<=chunks.length() {
        if end > 0 {
          let chunk = chunks[end - 1].to_string()
          prefix += chunk
          view.feed(chunk)
        }
        let full = rules.fold(init=prefix, (text, pair) => {
          text.replace_all(old=pair.0, new=pair.1)
        })
        assert_eq(
          view.snapshot(),
          (last_chars(full, n), full.char_length() > n),
        )
        view.feed("")
        assert_eq(
          view.snapshot(),
          (last_chars(full, n), full.char_length() > n),
        )
      }
    }
  }
}

///|
async test "late display registration joins a spilled UTF-8 prefix and future chunks" {
  let dir = @fs.tmpdir(prefix="openseek-display-tail-")
  defer @fs.remove(dir, recursive=true)
  let sink = ShellOutputSink(inline_cap=2, spill_path="\{dir}/out")
  defer sink.close()
  // Byte 65536 splits the emoji in the replay block; the search literal
  // straddles the registration point as well.
  let before = "x".repeat(65535) + "🌙/tm"
  sink.append_text(before)
  let view = sink.track_display_tail([("🌙/tmp", "source")], 12)
  assert_eq(view.snapshot(), (last_chars(before, 12), true))
  sink.append_chunk(b"p\r\nend")
  assert_eq(view.snapshot(), ("xsource\r\nend", true))
  assert_eq(sink.read_all(), before + "p\r\nend")
}

///|
async test "display views keep only successfully retained output" {
  let sink = ShellOutputSink(inline_cap=4, hard_cap=6)
  let early = sink.track_display_tail([("ab", "x")], 20)
  sink.append_text("abc")
  let late = sink.track_display_tail([("ab", "x")], 20)
  sink.append_text("defg")
  assert_eq(early.snapshot(), ("xcd", false))
  assert_eq(late.snapshot(), early.snapshot())
  assert_true(sink.truncated())
}

///|
async test "a live view crosses the first spill and ignores a failed write" {
  let dir = @fs.tmpdir(prefix="openseek-display-commit-")
  defer @fs.remove(dir, recursive=true)
  let path = "\{dir}/out"
  let sink = ShellOutputSink(inline_cap=2, hard_cap=10, spill_path=path)
  defer sink.close()
  let view = sink.track_display_tail([("abc", "s")], 8)
  sink.append_text("a")
  sink.append_text("bcdef")
  assert_eq(view.snapshot(), ("sdef", false))
  sink.close()
  sink.file = Some(@fs.open(path, mode=ReadOnly))
  try sink.append_text("more") catch {
    _ => assert_true(sink.failure is Some(_))
  } noraise {
    _ => fail("expected write failure")
  }
  assert_eq(view.snapshot(), ("sdef", false))
  assert_eq(sink.read_all(), "abcdef")
}
