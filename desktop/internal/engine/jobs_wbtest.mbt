///|
async test "job log pages follow byte cursors across multibyte output and no newline" {
  let root = @fs.tmpdir(prefix="job-page-")
  defer @fs.rmdir(root, recursive=true)
  let path = "\{root}/job.out"
  @fs.write_file(path, "a你好🙂tail")
  let first = read_job_page(path, Some(0L), 5)
  assert_eq(first.text, "a你")
  assert_eq(first.next_offset, 4L)
  let second = read_job_page(path, Some(first.next_offset), 4)
  assert_eq(second.text, "好")
  let third = read_job_page(path, Some(second.next_offset), 4)
  assert_eq(third.text, "🙂")
  let tail = read_job_page(path, None, 7)
  assert_eq(tail.text, "tail")
  assert_eq(tail.next_offset, 15L)
  @fs.write_file(path, "more", append=true, create_mode=OpenOrCreate)
  let more = read_job_page(path, Some(tail.next_offset), 65536)
  assert_eq(more.text, "more")
  assert_false(more.more)
  @fs.write_file(path, "short")
  try read_job_page(path, Some(more.next_offset), 65536) catch {
    EngineError(message) => assert_true(message.contains("truncated"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("truncation must be explicit")
  }
  @fs.remove(path)
  try read_job_page(path, None, 65536) catch {
    @os_error.OSError(_) as error => assert_true(error.is_ENOENT())
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("missing log must not read as empty")
  }
}

///|
async test "job output pages are bounded for a large retained file" {
  let root = @fs.tmpdir(prefix="job-large-")
  defer @fs.rmdir(root, recursive=true)
  let path = "\{root}/large.out"
  @fs.write_file(path, "x".repeat(200000))
  let page = read_job_page(path, Some(0L), 65536)
  assert_eq(page.text.length(), 65536)
  assert_true(page.more)
  let tail = read_job_page(path, None, 65536)
  assert_eq(tail.text.length(), 65536)
  assert_eq(tail.start_offset, 134464L)
  assert_eq(tail.next_offset, 200000L)
}

///|
fn job_record_fixture() -> @wire.JobRecord {
  {
    generation: "gen-1",
    id: "bg-1",
    revision: 1,
    command: "sleep 30",
    description: None,
    cwd: None,
    state: Running,
    started_at_ms: 1L,
    backgrounded_at_ms: 2L,
    finished_at_ms: None,
    last_output_at_ms: None,
    output_file: Some("fg-1.out"),
    output_persistent: true,
    output_bytes: 0L,
    output_chars: 0,
    output_truncated: false,
    invalid_utf8: false,
    output_error: None,
    persistence_error: None,
    cleanup_error: None,
  }
}

///|
async test "job history distinguishes dead owner from disconnected client and malformed metadata" {
  let root = @fs.tmpdir(prefix="job-history-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir("\{root}/gen-1")
  let record = job_record_fixture()
  @fs.write_file("\{root}/gen-1/bg-1.json", record.to_json().stringify())
  assert_eq(read_job_record(root, "gen-1", "bg-1"), record)
  let unknown = job_view(root, record, false)
  assert_true(unknown.error is Some(_))
  assert_true(unknown.job.state is Running)
  let owner = @fs.open(
    "\{root}/gen-1/owner.lock",
    mode=ReadWrite,
    create_mode=CreateNew,
  )
  owner.lock(Exclusive)
  let external = job_view(root, record, false)
  assert_true(external.job.state is Running)
  assert_false(external.controllable)
  owner.close()
  let interrupted = job_view(root, record, false)
  assert_true(interrupted.job.state is Interrupted)
  let live = job_view(root, record, true)
  assert_true(live.controllable)
  @fs.write_file("\{root}/gen-1/bg-1.json", "{}")
  try read_job_record(root, "gen-1", "bg-1") catch {
    _ => ()
  } noraise {
    _ => fail("corrupt metadata must not disappear silently")
  }
}
