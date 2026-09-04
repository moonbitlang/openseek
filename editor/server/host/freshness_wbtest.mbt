///|
fn freshness_test_path(raw : String) -> @workspace.SourcePath raise {
  match @workspace.SourcePath::normalize_root_relative_path(raw) {
    ParsedSourcePath(path) => path
    SourcePathError(error) => fail(error.to_string())
  }
}

///|
fn freshness_test_uri(raw : String) -> @base_common.Uri raise {
  match @server.remote_document_uri(raw) {
    Some(uri) => uri
    None => fail("invalid test URI")
  }
}

///|
async fn freshness_test_model(
  root : String,
  relative : String,
  text : String,
) -> @model.TextModel {
  let path = freshness_test_path(relative)
  guard read_native_disk_snapshot(root, path) is Some(disk) else {
    fail("expected native disk snapshot")
  }
  TextModel(
    freshness_test_uri(relative),
    relative,
    "moonbit",
    1,
    disk.signature,
    text,
  )
}

///|
async fn freshness_test_document(
  root : String,
  relative : String,
  text : String,
) -> @workspace.DocumentSnapshot {
  let path = freshness_test_path(relative)
  guard read_native_disk_snapshot(root, path) is Some(disk) else {
    fail("expected native disk snapshot")
  }
  DocumentSnapshot(
    freshness_test_uri(relative),
    relative,
    "moonbit",
    disk.signature,
    text,
  )
}

///|
fn hover_test_output() -> String {
  let raw =
    #|{"range":"1:1-1:4","contents":["hover"]}
  raw
}

///|
async test "native hover requires exact disk state and runs ordinary moon ide hover" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-hover-fresh")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn old {}\r\n",
      create_mode=CreateOrTruncate,
    )
    let model = freshness_test_model(root, "main.mbt", "pub fn old {}\n")
    defer model.dispose()
    let provider = MoonWorkspaceLanguageProvider(
      Ref(root),
      moon_command="unused",
    )
    let seen : Ref[Array[String]] = Ref([])
    let hover = provider.provide_hover_with_runner(model, Position(1, 8), (
      _root,
      args,
    ) => {
      seen.val = args
      Some((0, hover_test_output()))
    })
    assert_true(hover is Some(_))
    assert_eq(seen.val, [
      "ide", "hover", "--loc", "main.mbt:1:8", "--output-json",
    ])
    assert_false(seen.val.contains("--no-check"))
  }
}

///|
async test "native hover skips command for a mismatched request revision" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-hover-mismatch")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn old {}\n",
      create_mode=CreateOrTruncate,
    )
    let model = @model.TextModel(
      freshness_test_uri("main.mbt"),
      "main.mbt",
      "moonbit",
      1,
      "wrong-revision",
      "pub fn old {}\n",
    )
    defer model.dispose()
    let calls = Ref(0)
    let provider = MoonWorkspaceLanguageProvider(
      Ref(root),
      moon_command="unused",
    )
    let hover = provider.provide_hover_with_runner(model, Position(1, 8), (
      _root,
      _args,
    ) => {
      calls.val += 1
      Some((0, hover_test_output()))
    })
    assert_true(hover is None)
    assert_eq(calls.val, 0)
  }
}

///|
async test "native hover drops a disk change during the command" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-hover-race")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn old {}\n",
      create_mode=CreateOrTruncate,
    )
    let model = freshness_test_model(root, "main.mbt", "pub fn old {}\n")
    defer model.dispose()
    let started = @async.Semaphore(1, initial_value=0)
    let release_gate = @async.Semaphore(1, initial_value=0)
    let provider = MoonWorkspaceLanguageProvider(
      Ref(root),
      moon_command="unused",
    )
    let request = group.spawn(() => {
      provider.provide_hover_with_runner(model, Position(1, 8), (_root, _args) => {
        started.release()
        release_gate.acquire()
        Some((0, hover_test_output()))
      })
    })
    started.acquire()
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn new {}\n",
      create_mode=CreateOrTruncate,
    )
    release_gate.release()
    assert_true(request.wait() is None)
  }
}

///|
async test "native document reads reuse one coherent text and revision snapshot" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-document-snapshot")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn main {}\r\n",
      create_mode=CreateOrTruncate,
    )
    let path = freshness_test_path("main.mbt")
    guard read_native_disk_snapshot(root, path) is Some(snapshot) else {
      fail("expected coherent disk snapshot")
    }
    match read_native_text_file(root, path) {
      ServerHostReadOk(content) => {
        let document = @workspace.DocumentSnapshot::from_content(
          @base_common.Uri::file(root + "/main.mbt"),
          content,
        )
        assert_eq(document.text, snapshot.text)
        assert_eq(document.revision, snapshot.signature)
      }
      ServerHostReadError(_code, message) => fail(message)
    }
  }
}

///|
async test "native coherent snapshot rejects invalid utf8 and disappearing entries" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-document-invalid")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    let invalid = Bytes::from_array([0xff, 0xfe])
    @fs.write_file("\{root}/invalid.mbt", invalid, create_mode=CreateOrTruncate)
    let invalid_path = freshness_test_path("invalid.mbt")
    assert_true(read_native_disk_snapshot(root, invalid_path) is None)
    match read_native_text_file(root, invalid_path) {
      ServerHostReadError(code, _) => assert_true(code == Unavailable)
      ServerHostReadOk(_) => fail("expected invalid UTF-8 rejection")
    }
    let missing_path = freshness_test_path("missing.mbt")
    assert_true(read_native_disk_snapshot(root, missing_path) is None)
    @fs.mkdir("\{root}/directory.mbt")
    let directory_path = freshness_test_path("directory.mbt")
    assert_true(read_native_disk_snapshot(root, directory_path) is None)
  }
}

///|
priv struct CheckPublishEvent {
  uri : String
  revision : String
  diagnostics : Array[@language.Diagnostic]
}

///|
priv struct ControlledCheck {
  calls : Ref[Int]
  started : @aqueue.Queue[Int]
  release_gate : @aqueue.Queue[String]
}

///|
async fn ControlledCheck::collect(self : ControlledCheck) -> String? {
  self.calls.val += 1
  self.started.put(self.calls.val)
  Some(self.release_gate.get())
}

///|
fn check_test_output(root : String, message : String) -> String {
  check_test_file_output(root, "main.mbt", message)
}

///|
fn check_test_file_output(
  root : String,
  relative : String,
  message : String,
) -> String {
  // JSON-escape the path: on Windows the tmpdir root contains backslashes,
  // which are invalid raw inside a JSON string. The real `moon check
  // --output-json` escapes paths the same way.
  let path = Json::string("\{root}/\{relative}").stringify()
  "{\"$message_type\":\"diagnostic\",\"level\":\"warning\",\"path\":\{path},\"loc\":\"1:1-1:4\",\"message\":\"\{message}\"}"
}

///|
fn controlled_diagnostics(
  root : String,
  control : ControlledCheck,
  events : Array[CheckPublishEvent],
) -> MoonCheckDiagnostics {
  new_moon_check_diagnostics(
    Ref(root),
    (uri, revision, diagnostics) => {
      events.push({ uri: uri.to_string(), revision, diagnostics, })
    },
    () => control.collect(),
  )
}

///|
fn check_event_count(events : Array[CheckPublishEvent], uri : String) -> Int {
  for event in events; count = 0 {
    if event.uri == uri {
      continue count + 1
    }
  } nobreak {
    count
  }
}

///|
fn last_check_event(
  events : Array[CheckPublishEvent],
  uri : String,
) -> CheckPublishEvent? {
  for event in events; found = None {
    if event.uri == uri {
      continue Some(event)
    }
  } nobreak {
    found
  }
}

///|
async fn wait_for_check_idle(diagnostics : MoonCheckDiagnostics) -> Unit {
  let mut remaining = 200
  while diagnostics.running.val && remaining > 0 {
    @async.sleep(5)
    remaining -= 1
  }
  if diagnostics.running.val {
    fail("timed out waiting for diagnostics runner")
  }
}

///|
async test "moon check replays only an exact producing document state" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-check-replay")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn old {}\n",
      create_mode=CreateOrTruncate,
    )
    let old_document = freshness_test_document(
      root, "main.mbt", "pub fn old {}\n",
    )
    let control : ControlledCheck = {
      calls: Ref(0),
      started: Queue(kind=Unbounded),
      release_gate: Queue(kind=Unbounded),
    }
    let events : Array[CheckPublishEvent] = []
    let diagnostics = controlled_diagnostics(root, control, events)
    diagnostics.note_document(old_document)
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 1)
    control.release_gate.put(check_test_output(root, "old"))
    wait_for_check_idle(diagnostics)
    assert_eq(events.length(), 1)
    assert_eq(events[0].revision, old_document.revision)
    assert_eq(events[0].diagnostics[0].message, "old")

    diagnostics.note_document(old_document)
    assert_eq(events.length(), 2)
    assert_eq(events[1].revision, old_document.revision)

    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn new {}\n",
      create_mode=CreateOrTruncate,
    )
    let new_document = freshness_test_document(
      root, "main.mbt", "pub fn new {}\n",
    )
    diagnostics.note_document(new_document)
    assert_eq(events.length(), 2)
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 2)
    control.release_gate.put(check_test_output(root, "new"))
    wait_for_check_idle(diagnostics)
    assert_eq(events.length(), 3)
    assert_eq(events[2].revision, new_document.revision)
    assert_eq(events[2].diagnostics[0].message, "new")
  }
}

///|
async test "document sync during moon check discards output and reruns once" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-check-sync-race")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn old {}\n",
      create_mode=CreateOrTruncate,
    )
    let old_document = freshness_test_document(
      root, "main.mbt", "pub fn old {}\n",
    )
    let control : ControlledCheck = {
      calls: Ref(0),
      started: Queue(kind=Unbounded),
      release_gate: Queue(kind=Unbounded),
    }
    let events : Array[CheckPublishEvent] = []
    let diagnostics = controlled_diagnostics(root, control, events)
    diagnostics.note_document(old_document)
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 1)
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn new {}\n",
      create_mode=CreateOrTruncate,
    )
    let new_document = freshness_test_document(
      root, "main.mbt", "pub fn new {}\n",
    )
    diagnostics.note_document(new_document)
    control.release_gate.put(check_test_output(root, "stale"))
    assert_eq(control.started.get(), 2)
    control.release_gate.put(check_test_output(root, "fresh"))
    wait_for_check_idle(diagnostics)
    assert_eq(control.calls.val, 2)
    assert_eq(events.length(), 1)
    assert_eq(events[0].revision, new_document.revision)
    assert_eq(events[0].diagnostics[0].message, "fresh")
  }
}

///|
async test "disk-only change during moon check reruns and publishes nothing" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-check-disk-race")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn old {}\n",
      create_mode=CreateOrTruncate,
    )
    let document = freshness_test_document(root, "main.mbt", "pub fn old {}\n")
    let control : ControlledCheck = {
      calls: Ref(0),
      started: Queue(kind=Unbounded),
      release_gate: Queue(kind=Unbounded),
    }
    let events : Array[CheckPublishEvent] = []
    let diagnostics = controlled_diagnostics(root, control, events)
    diagnostics.note_document(document)
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 1)
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn new {}\n",
      create_mode=CreateOrTruncate,
    )
    control.release_gate.put(check_test_output(root, "raced"))
    assert_eq(control.started.get(), 2)
    control.release_gate.put(check_test_output(root, "incompatible"))
    wait_for_check_idle(diagnostics)
    assert_eq(control.calls.val, 2)
    assert_eq(events.length(), 0)
  }
}

///|
async test "stable incompatible rerun preserves a prior published set silently" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-check-preserve")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn old {}\n",
      create_mode=CreateOrTruncate,
    )
    let document = freshness_test_document(root, "main.mbt", "pub fn old {}\n")
    let control : ControlledCheck = {
      calls: Ref(0),
      started: Queue(kind=Unbounded),
      release_gate: Queue(kind=Unbounded),
    }
    let events : Array[CheckPublishEvent] = []
    let diagnostics = controlled_diagnostics(root, control, events)
    diagnostics.note_document(document)
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 1)
    control.release_gate.put(check_test_output(root, "accepted"))
    wait_for_check_idle(diagnostics)
    assert_eq(events.length(), 1)

    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 2)
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn new {}\n",
      create_mode=CreateOrTruncate,
    )
    control.release_gate.put(check_test_output(root, "raced"))
    assert_eq(control.started.get(), 3)
    control.release_gate.put(check_test_output(root, "incompatible"))
    wait_for_check_idle(diagnostics)

    // Neither the raced output nor the stable disk/model mismatch emits.
    assert_eq(events.length(), 1)
    assert_eq(control.calls.val, 3)
    let key = freshness_test_uri("main.mbt").to_string()
    guard diagnostics.published.val.get(key) is Some(published) else {
      fail("expected the prior accepted set to remain stored")
    }
    assert_eq(published.revision, document.revision)
    assert_eq(published.diagnostics[0].message, "accepted")
  }
}

///|
async test "historical incompatible document does not suppress active diagnostics" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-check-per-document")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/historical.mbt",
      "pub fn historical {}\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/active.mbt",
      "pub fn active {}\n",
      create_mode=CreateOrTruncate,
    )
    let historical = freshness_test_document(
      root, "historical.mbt", "pub fn historical {}\n",
    )
    let active = freshness_test_document(
      root, "active.mbt", "pub fn active {}\n",
    )
    let control : ControlledCheck = {
      calls: Ref(0),
      started: Queue(kind=Unbounded),
      release_gate: Queue(kind=Unbounded),
    }
    let events : Array[CheckPublishEvent] = []
    let diagnostics = controlled_diagnostics(root, control, events)
    diagnostics.note_document(historical)
    diagnostics.note_document(active)
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 1)
    control.release_gate.put(
      (
        $|\{check_test_file_output(root, "historical.mbt", "accepted historical")}
        $|\{check_test_file_output(root, "active.mbt", "accepted active")}
      ),
    )
    wait_for_check_idle(diagnostics)
    let historical_key = historical.uri.to_string()
    let active_key = active.uri.to_string()
    assert_eq(check_event_count(events, historical_key), 1)
    assert_eq(check_event_count(events, active_key), 1)

    // There is no diagnostics close notification yet, so this stale document
    // remains in `documents` after its file disappears.
    @fs.remove("\{root}/historical.mbt")
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 2)
    control.release_gate.put(
      (
        $|\{check_test_file_output(root, "historical.mbt", "must be ignored")}
        $|\{check_test_file_output(root, "active.mbt", "updated active")}
        $|\{check_test_file_output(root, "unknown.mbt", "unknown")}
      ),
    )
    wait_for_check_idle(diagnostics)
    assert_eq(check_event_count(events, historical_key), 1)
    assert_eq(check_event_count(events, active_key), 2)
    guard last_check_event(events, active_key) is Some(active_update) else {
      fail("expected active diagnostic update")
    }
    assert_eq(active_update.diagnostics[0].message, "updated active")

    // A following compatible run can clear B while incompatible A remains
    // silent and retains its previously accepted set.
    diagnostics.schedule(task => group.spawn_bg(task))
    assert_eq(control.started.get(), 3)
    control.release_gate.put(
      check_test_file_output(root, "unknown.mbt", "still unknown"),
    )
    wait_for_check_idle(diagnostics)
    assert_eq(check_event_count(events, historical_key), 1)
    assert_eq(check_event_count(events, active_key), 3)
    guard last_check_event(events, active_key) is Some(active_clear) else {
      fail("expected active diagnostic clear")
    }
    assert_true(active_clear.diagnostics.is_empty())

    guard diagnostics.published.val.get(historical_key) is Some(historical_set) else {
      fail("expected historical diagnostics to remain stored")
    }
    assert_eq(historical_set.diagnostics[0].message, "accepted historical")
    assert_false(diagnostics.published.val.contains(active_key))
    assert_false(
      diagnostics.published.val.contains(
        freshness_test_uri("unknown.mbt").to_string(),
      ),
    )
  }
}

///|
priv suberror CheckCollectorFailure {
  CheckCollectorFailure
}

///|
async test "moon check schedule restores running after collector failure" {
  let diagnostics = new_moon_check_diagnostics(
    Ref("/workspace"),
    (_uri, _revision, _diagnostics) => (),
    () => raise CheckCollectorFailure,
  )
  let scheduled : Ref[(async () -> Unit)?] = Ref(None)
  diagnostics.schedule(task => scheduled.val = Some(task))
  guard scheduled.val is Some(run) else {
    fail("expected a scheduled diagnostics task")
  }
  @async.with_task_group() <| group => {
    let task = group.spawn(() => run(), allow_failure=true)
    let caught = Ref(false)
    task.wait() catch {
      CheckCollectorFailure => caught.val = true
      _ => ()
    }
    assert_true(caught.val)
    assert_false(diagnostics.running.val)
  }
}

///|
async test "moon check schedule restores running after cancellation" {
  let started = @aqueue.Queue(kind=Unbounded)
  let release_gate = @aqueue.Queue(kind=Unbounded)
  let diagnostics = new_moon_check_diagnostics(
    Ref("/workspace"),
    (_uri, _revision, _diagnostics) => (),
    () => {
      started.put(())
      release_gate.get()
      None
    },
  )
  let scheduled : Ref[(async () -> Unit)?] = Ref(None)
  diagnostics.schedule(task => scheduled.val = Some(task))
  guard scheduled.val is Some(run) else {
    fail("expected a scheduled diagnostics task")
  }
  @async.with_task_group() <| group => {
    let task = group.spawn(() => run(), allow_failure=true)
    started.get()
    task.cancel()
    let cancelled = Ref(false)
    task.wait() catch {
      error => cancelled.val = @async.is_cancellation_error(error)
    }
    assert_true(cancelled.val)
    assert_false(diagnostics.running.val)
  }
}
