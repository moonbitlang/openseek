// Serving a background job's record and output: the route the waterfall's job
// rows call when a reader opens one.

///|
/// The store a job record lives in: `<base>/<label>/sessions/<id>/jobs` beside
/// the session file, the shape the engine writes.
async fn job_fixture(
  root : String,
  label : String,
  session_id : String,
  generation : String,
  job_id : String,
  record_fields : Map[String, Json],
) -> String {
  let directory = "\{root}/\{label}/sessions/\{session_id}/jobs/\{generation}"
  @fs.mkdir(directory, recursive=true, allow_existing=true)
  let fields = record_fields.copy()
  fields["schema_version"] = Json(1)
  fields["generation"] = Json(generation)
  fields["id"] = Json(job_id)
  let path = "\{directory}/\{job_storage_name(job_id)}.json"
  @fs.write_text(
    path,
    Json::object(fields).stringify(),
    create_mode=CreateOrTruncate,
  )
  path
}

///|
/// A record with the fields the viewer reads; `output_file` names a file the
/// caller writes beside it.
fn job_fields(
  started_at_ms : Int64,
  output_file : String?,
  output_bytes : Int64,
) -> Map[String, Json] {
  let fields : Map[String, Json] = {
    "state": { "kind": "exited", "code": 0 },
    "command": "mbtx run build.mbtx",
    "started_at_ms": Json(started_at_ms.to_double()),
    "finished_at_ms": Json((started_at_ms + 1_200L).to_double()),
    "output_bytes": Json(output_bytes.to_double()),
    "output_persistent": Json(true),
    "output_chars": Json(output_bytes),
    "output_truncated": Json(false),
    "invalid_utf8": Json(false),
  }
  match output_file {
    Some(file) => fields["output_file"] = Json(file)
    None => ()
  }
  fields
}

///|
/// One generation holding one job whose output is the generation's own name,
/// so a reply tells which record answered.
async fn seed_job(
  root : String,
  generation : String,
  job_id : String,
  started_at_ms : Int64,
) -> Unit {
  ignore(
    job_fixture(
      root,
      ".openseek",
      "run",
      generation,
      job_id,
      job_fields(
        started_at_ms,
        Some("bg-1.out"),
        generation.length().to_int64(),
      ),
    ),
  )
  @fs.write_text(
    "\{root}/.openseek/sessions/run/jobs/\{generation}/bg-1.out",
    generation,
    create_mode=CreateOrTruncate,
  )
}

///|
async fn job_body(
  catalog : SessionCatalog,
  rest : String,
  request_path~ : String,
) -> Json {
  let reply = session_path_reply(catalog, rest, request_path~)
  inspect(reply.code, content="200")
  @json.parse(reply.body) catch {
    _ => fail("job reply must be JSON")
  }
}

///|
async test "job route serves a record and the tail of its output" {
  @vfs.with_tmpdir(prefix="openseek-viz-job-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="").append(
        User(UserMessage(Content([Text("run a job")]))),
      ),
    )
    let generation = "openseek-jobs-.42.abcd1234"
    let job = "AaG2AvuPcC-Cmc3vfVAitA"
    let directory = "\{root}/.openseek/sessions/run/jobs/\{generation}"
    ignore(
      job_fixture(
        root,
        ".openseek",
        "run",
        generation,
        job,
        job_fields(1_000L, Some("fg-1.out"), 11L),
      ),
    )
    @fs.write_text(
      "\{directory}/fg-1.out",
      "hello world",
      create_mode=CreateOrTruncate,
    )
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let body = job_body(
      catalog,
      "run/jobs/\{job}",
      request_path="/api/sessions/run/jobs/\{job}",
    )
    guard body
      is { "found": True, "job": Object(record), "output": Object(output), .. } else {
      fail("expected a found job with output")
    }
    guard record.get("id") is Some(String(id)) else { fail("record id") }
    assert_eq(id, job)
    guard record.get("generation") is Some(String(seen)) else {
      fail("record generation")
    }
    assert_eq(seen, generation)
    guard record.get("state") is Some({ "kind": String(kind), .. }) else {
      fail("record state")
    }
    assert_eq(kind, "exited")
    guard output.get("text") is Some(String(text)) else { fail("output text") }
    assert_eq(text, "hello world")
    guard output.get("head_omitted") is Some(False) else {
      fail("a whole file is not a tail")
    }
    guard output.get("size") is Some(Number(size, ..)) else {
      fail("output size")
    }
    assert_eq(size.to_int64(), 11L)
  })
}

///|
async test "job route cuts a long log to its tail and continues from a cursor" {
  @vfs.with_tmpdir(prefix="openseek-viz-job-tail-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="").append(
        User(UserMessage(Content([Text("x")]))),
      ),
    )
    let generation = "gen-1"
    let job = "job-1"
    let directory = "\{root}/.openseek/sessions/run/jobs/\{generation}"
    // 70 KiB of padding plus a last line, so the tail window cannot hold the
    // whole file and the reader is told so.
    let padding = "a".repeat(70 * 1024)
    let text = "\{padding}THE-END\n"
    ignore(
      job_fixture(
        root,
        ".openseek",
        "run",
        generation,
        job,
        job_fields(2_000L, Some("fg-1.out"), text.length().to_int64()),
      ),
    )
    @fs.write_text("\{directory}/fg-1.out", text, create_mode=CreateOrTruncate)
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let body = job_body(
      catalog,
      "run/jobs/\{job}",
      request_path="/api/sessions/run/jobs/\{job}",
    )
    guard body is { "output": Object(output), .. } else {
      fail("expected output")
    }
    guard output.get("text") is Some(String(tail)) else { fail("tail text") }
    assert_true(tail.has_suffix("THE-END\n"))
    guard output.get("head_omitted") is Some(True) else {
      fail("an earlier part of the log is not shown, and the reply must say so")
    }
    guard output.get("start_offset") is Some(Number(start, ..)) else {
      fail("start offset")
    }
    assert_true(start.to_int64() > 0L)
    // A cursor asks for what was appended since, not for the tail again.
    let head = job_body(
      catalog,
      "run/jobs/\{job}",
      request_path="/api/sessions/run/jobs/\{job}?cursor=0",
    )
    guard head is { "output": Object(head_output), .. } else {
      fail("expected output")
    }
    guard head_output.get("text") is Some(String(head_text)) else {
      fail("cursor text")
    }
    assert_eq(head_text.length(), 65536)
    guard head_output.get("head_omitted") is Some(False) else {
      fail("a cursor read does not omit anything before it")
    }
    // A cursor past the end means the file was rewritten: say so instead of
    // pretending the reader is caught up.
    let stale = job_body(
      catalog,
      "run/jobs/\{job}",
      request_path="/api/sessions/run/jobs/\{job}?cursor=999999999",
    )
    guard stale is { "output": Object(stale_output), .. } else {
      fail("expected output")
    }
    guard stale_output.get("stale") is Some(True) else {
      fail("a cursor past the end is stale")
    }
  })
}

///|
async test "job route prefers the generation that started when the span did" {
  @vfs.with_tmpdir(prefix="openseek-viz-job-gen-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="").append(
        User(UserMessage(Content([Text("x")]))),
      ),
    )
    // A legacy counter reused across two engine runs of the same session.
    seed_job(root, "gen-old", "bg-1", 1_000L)
    seed_job(root, "gen-new", "bg-1", 90_000L)
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    // Without a hint the newest record wins.
    let newest = job_body(
      catalog,
      "run/jobs/bg-1",
      request_path="/api/sessions/run/jobs/bg-1",
    )
    guard newest is { "output": Object(output), .. } else { fail("output") }
    guard output.get("text") is Some(String(text)) else { fail("text") }
    assert_eq(text, "gen-new")
    // With the span's own start, the generation that was running then wins.
    let older = job_body(
      catalog,
      "run/jobs/bg-1",
      request_path="/api/sessions/run/jobs/bg-1?start=1500",
    )
    guard older is { "output": Object(older_output), .. } else {
      fail("output")
    }
    guard older_output.get("text") is Some(String(older_text)) else {
      fail("text")
    }
    assert_eq(older_text, "gen-old")
  })
}

///|
async test "job route answers a miss without inventing a record" {
  @vfs.with_tmpdir(prefix="openseek-viz-job-miss-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="").append(
        User(UserMessage(Content([Text("x")]))),
      ),
    )
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    // No job store beside the session at all: an archive of copied logs.
    let missing = job_body(
      catalog,
      "run/jobs/bg-1",
      request_path="/api/sessions/run/jobs/bg-1",
    )
    guard missing is { "found": False, "error": String(_), .. } else {
      fail("a session with no job store answers found=false")
    }
    // A job id that is not a storage component never becomes a path.
    let escaped = job_body(
      catalog,
      "run/jobs/..%2F..%2Fetc",
      request_path="/api/sessions/run/jobs/..%2F..%2Fetc",
    )
    guard escaped is { "found": False, .. } else {
      fail("a path-shaped job id must not resolve")
    }
    // A record whose id does not match its storage name is a miss, not a hit.
    let generation = "gen-1"
    let directory = "\{root}/.openseek/sessions/run/jobs/\{generation}"
    @fs.mkdir(directory, recursive=true, allow_existing=true)
    @fs.write_text(
      "\{directory}/\{job_storage_name("other")}.json",
      Json::object(job_fields(1_000L, None, 0L)).stringify(),
      create_mode=CreateOrTruncate,
    )
    let wrong = job_body(
      catalog,
      "run/jobs/bg-1",
      request_path="/api/sessions/run/jobs/bg-1",
    )
    guard wrong is { "found": False, .. } else {
      fail("a record must match the id it was asked for")
    }
  })
}

///|
test "job storage names are reversible, and only for compact handles" {
  assert_eq(job_storage_name("bg-1"), "bg-1")
  assert_eq(
    job_storage_name("AaG2AvuPcC-Cmc3vfVAitA"),
    "uuid-01a1b602fb8f702f8299cdef7d5022b4",
  )
}
