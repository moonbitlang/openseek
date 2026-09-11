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

///|
async test "history decodes only its requested page and preserves runtime job order" {
  let root = @fs.tmpdir(prefix="job-history-pages-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir("\{root}/gen-1")
  @fs.write_file("\{root}/gen-1/owner.lock", "")
  for index in 1..<=101 {
    let record = {
      ..job_record_fixture(),
      id: "bg-\{index}",
      state: Exited(0),
    }
    @fs.write_file(
      "\{root}/gen-1/bg-\{index}.json",
      if index == 1 {
        "corrupt old metadata"
      } else {
        record.to_json().stringify()
      },
    )
  }
  let first = job_history_page(root, Map([]), 0, [])
  assert_eq(first.jobs.length(), 100)
  assert_eq(first.jobs[0].job.id, "bg-101")
  assert_eq(first.jobs[99].job.id, "bg-2")
  assert_eq(first.next_offset, Some(100))
  assert_true(first.errors.is_empty())
  let second = job_history_page(root, Map([]), 100, [])
  assert_true(second.jobs.is_empty())
  assert_true(second.next_offset is None)
  assert_eq(second.errors.length(), 1)
  assert_true(second.errors[0].contains("bg-1"))
  // Selection is refreshed independently of the visible history page, and a
  // live snapshot remains usable even if its metadata write failed.
  let terminal = {
    ..job_record_fixture(),
    state: Stopped("user"),
    revision: 3,
  }
  let selected = selected_job_view(
    root,
    Map([("gen-1/bg-1", terminal)]),
    "gen-1",
    "bg-1",
  )
  assert_eq(selected.job, terminal)
  assert_false(selected.controllable)
  // One malformed runtime entry produces one actionable diagnostic.
  // Use an otherwise empty root so pagination cannot hide a second error.
  let broken_root = @fs.tmpdir(prefix="job-broken-runtime-")
  defer @fs.rmdir(broken_root, recursive=true)
  @fs.write_file("\{broken_root}/stray-file", "not a runtime directory")
  let broken = job_history_page(broken_root, Map([]), 0, [])
  assert_eq(broken.errors.length(), 1)
  assert_true(broken.errors[0].contains("stray-file"))
}

///|
#cfg(not(platform="windows"))
async test "owner lock inspection failures preserve durable and live jobs" {
  let root = @fs.tmpdir(prefix="job-owner-inspection-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir("\{root}/gen-1")
  let record = job_record_fixture()
  @fs.write_file("\{root}/gen-1/bg-1.json", record.to_json().stringify())
  // A symlink loop produces a non-ENOENT stat failure even when run as root.
  @fs.symlink(target="owner.lock", "\{root}/gen-1/owner.lock")
  let durable = job_history_page(root, Map([]), 0, [])
  assert_eq(durable.jobs.length(), 1)
  assert_true(durable.jobs[0].job.state is Running)
  assert_true(durable.jobs[0].error is Some(_))
  assert_eq(durable.errors.length(), 1)
  let live = job_history_page(root, Map([("gen-1/bg-1", record)]), 0, [])
  assert_eq(live.jobs.length(), 1)
  assert_true(live.jobs[0].controllable)
  assert_eq(live.errors.length(), 1)
}

///|
test "log cursors reject UTF8 continuation boundaries and invalid trailing leads" {
  for bytes in [b"\x80", b"a\xc0", b"a\xff"] {
    try job_utf8_window(bytes, false) catch {
      _ => ()
    } noraise {
      _ => fail("invalid bytes must not produce a nonadvancing cursor")
    }
  }
  assert_eq(job_utf8_window(b"a\xf0\x9f", false), (0, 1))
}

///|
#cfg(platform="windows")
test "job ownership paths normalize Windows joins and engine roots equally" {
  let native = @pathx.Path("C:\\workspace\\.openseek").resolve()
  assert_eq(
    jobs_store_path(native, "s-1"),
    "C:/workspace/.openseek/sessions/s-1/jobs",
  )
  assert_eq(
    jobs_store_path(native, "s-1"),
    jobs_store_path(native.normalize(), "s-1"),
  )
}

///|
#cfg(not(platform="windows"))
test "job ownership paths normalize POSIX roots and joins equally" {
  let root = @pathx.Path("/workspace/./.openseek").resolve()
  assert_eq(
    jobs_store_path(root, "s-1"),
    "/workspace/.openseek/sessions/s-1/jobs",
  )
  assert_eq(
    jobs_store_path(root, "s-1"),
    jobs_store_path(root.normalize(), "s-1"),
  )
}

///|
async test "a tail at byte zero rejects corrupt leading UTF8 instead of hiding it" {
  let root = @fs.tmpdir(prefix="job-invalid-tail-")
  defer @fs.rmdir(root, recursive=true)
  let path = "\{root}/output"
  @fs.write_file(path, b"\x80a")
  try read_job_page(path, None, 65536) catch {
    _ => ()
  } noraise {
    _ => fail("invalid leading UTF8 must remain visible as a read error")
  }
}
