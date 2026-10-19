///|
fn history_record(generation : String, id : String) -> @protocol.JobRecord {
  {
    generation,
    id,
    revision: 3,
    command: "openseek run --kind worker",
    description: Some("upgrade a"),
    cwd: Some("/work/a"),
    state: Running,
    started_at_ms: 100L,
    backgrounded_at_ms: 100L,
    finished_at_ms: None,
    last_output_at_ms: None,
    output_file: None,
    output_persistent: true,
    output_bytes: 0L,
    output_chars: 0,
    output_truncated: false,
    invalid_utf8: false,
    output_error: None,
    persistence_error: None,
    cleanup_error: None,
    data: None,
    subagent: None,
  }
}

///|
/// Store `record` in its generation under `root`, as an engine publishes it.
async fn store_record(root : String, record : @protocol.JobRecord) -> Unit {
  let directory = "\{root}/\{record.generation}"
  @fs.mkdir(directory, recursive=true, allow_exist=true)
  @fs.write_file(
    "\{directory}/\{@protocol.job_storage_name(record.id)}.json",
    record.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
}

///|
async fn owner_lock(root : String, generation : String) -> @fs.File {
  @fs.open(
    "\{root}/\{generation}/owner.lock",
    mode=ReadWrite,
    create_mode=CreateOrTruncate,
  )
}

///|
/// What an earlier engine left is read back, and only that: a generation whose
/// engine still holds its lock, this engine's own, a generation with no lock,
/// and a record that does not match its file are left out. Nothing is created.
async test "earlier job records are read from generations whose engine is gone" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="openseek-job-history-")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    // A dead engine's generation: its lock is free.
    store_record(root, history_record("gen-dead", "uuid-1"))
    store_record(root, history_record("gen-dead", "uuid-2"))
    owner_lock(root, "gen-dead").close()
    // A record stored under another job's name is not this file's.
    @fs.write_file(
      "\{root}/gen-dead/\{@protocol.job_storage_name("uuid-9")}.json",
      history_record("gen-dead", "uuid-3").to_json().stringify(),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/gen-dead/broken.json",
      "{",
      create_mode=CreateOrTruncate,
    )
    // A live engine's generation: its lock is held.
    store_record(root, history_record("gen-live", "uuid-4"))
    let held = owner_lock(root, "gen-live")
    defer held.close()
    held.lock(Exclusive)
    // A generation with no lock to check, and this engine's own.
    store_record(root, history_record("gen-unknown", "uuid-5"))
    store_record(root, history_record("gen-own", "uuid-6"))
    owner_lock(root, "gen-own").close()
    let records = @bgjobs.earlier_job_records(root, own="gen-own")
    assert_eq(records.map(record => record.id), ["uuid-1", "uuid-2"])
    // A session that never ran a job has no jobs root, and gets one from
    // nothing.
    assert_eq(
      @bgjobs.earlier_job_records("\{root}/absent", own="x").length(),
      0,
    )
    assert_false(@fs.exists("\{root}/absent"))
  })
}
