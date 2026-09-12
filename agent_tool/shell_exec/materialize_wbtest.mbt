///|
async test "background materialization seeds small output and preserves an empty file" {
  let dir = @fs.tmpdir(prefix="openseek-materialize-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/output.log"
  let sink = ShellOutputSink(inline_cap=100, spill_path=path)
  defer sink.close()
  sink.materialize()
  assert_true(@fs.exists(path))
  assert_eq(@fs.read_file(path).text(), "")
  sink.append_chunk(b"early")
  assert_eq(@fs.read_file(path).text(), "early")
  sink.materialize()
  sink.append_text(" later")
  assert_eq(@fs.read_file(path).text(), "early later")
  sink.close()
  assert_eq(sink.read_all(), "early later")
  assert_eq(sink.read_tail(5), "later")
}

///|
async test "materialization serializes with the writer and retains split UTF-8" {
  let dir = @fs.tmpdir(prefix="openseek-materialize-race-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/output.log"
  let sink = ShellOutputSink(inline_cap=10000, spill_path=path)
  defer sink.close()
  sink.append_chunk(([0x63, 0x61, 0x66, 0xc3] : Bytes))
  assert_false(@fs.exists(path))
  @async.with_task_group(group => {
    group.spawn_bg(() => sink.materialize())
    group.spawn_bg(() => {
      sink.append_chunk(([0xa9] : Bytes))
      for _ in 0..<100 {
        sink.append_text("\n进度")
      }
    })
  })
  sink.finish()
  let expected = "café"
  assert_true(@fs.read_file(path).text().has_prefix(expected))
  assert_eq(@fs.read_file(path).text(), sink.head())
  assert_eq(sink.size(), 304)
}

///|
async test "a failed log write never advances the committed offset or hides the failure" {
  let dir = @fs.tmpdir(prefix="openseek-log-error-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/output.log"
  let sink = ShellOutputSink(inline_cap=100, spill_path=path)
  defer sink.close()
  sink.append_text("before")
  sink.materialize()
  let committed = sink.file_bytes
  sink.close()
  sink.file = Some(@fs.open(path, mode=ReadOnly))
  try sink.append_text("after") catch {
    _ => assert_true(sink.failure is Some(_))
  } noraise {
    _ => fail("expected write failure")
  }
  assert_eq(sink.file_bytes, committed)
  assert_eq(sink.read_all(), "before")
}

///|
async test "file creation and read failures are distinct from an empty log" {
  let dir = @fs.tmpdir(prefix="openseek-log-missing-")
  defer @fs.rmdir(dir, recursive=true)
  let bad = ShellOutputSink(inline_cap=100, spill_path="\{dir}/missing/out")
  try bad.materialize() catch {
    _ => assert_true(bad.failure is Some(_))
  } noraise {
    _ => fail("expected creation failure")
  }
  let path = "\{dir}/out"
  let sink = ShellOutputSink(inline_cap=100, spill_path=path)
  sink.materialize()
  sink.close()
  @fs.remove(path)
  try sink.read_tail(100) catch {
    _ => ()
  } noraise {
    _ => fail("expected read failure")
  }
}

///|
async test "full reads remain consistent while output is appended" {
  let dir = @fs.tmpdir(prefix="openseek-read-prefix-")
  defer @fs.rmdir(dir, recursive=true)
  let sink = ShellOutputSink(inline_cap=100, spill_path="\{dir}/log")
  defer sink.close()
  let prefix = "你好🙂".repeat(100000)
  sink.append_text(prefix)
  @async.with_task_group(group => {
    let read = group.spawn(() => sink.read_all())
    sink.append_text("end")
    let text = read.wait()
    assert_true(text == prefix || text == prefix + "end")
  })
  assert_eq(sink.read_all(), prefix + "end")
}

///|
async test "a failed seed keeps the captured head readable and partial path inspectable" {
  let dir = @fs.tmpdir(prefix="openseek-seed-failure-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/log"
  let sink = ShellOutputSink(inline_cap=100, spill_path=path)
  sink.append_text("captured before adoption")
  // Inject the state left by a partial initial write: the path exists but
  // no complete write was committed. Do not replace the retained memory head.
  @fs.write_file(path, "captured")
  sink.file_created = true
  sink.failure = Some("seed write failed")
  assert_eq(sink.file_bytes, 0L)
  assert_eq(sink.spill_path(), Some(path))
  assert_eq(sink.read_all(), "captured before adoption")
  assert_true(sink.failure is Some(_))
}
