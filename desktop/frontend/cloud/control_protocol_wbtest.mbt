///|
fn control_snapshot_fixture() -> Json {
  {
    "session_id": "session",
    "task_id": "task",
    "seq": 3,
    "data": {
      "active_task_id": "task",
      "status": "running",
      "paused": false,
      "queue": [{ "id": "queued", "content": "next" }],
      "steers": [{ "submission_id": "steered", "status": "pending" }],
    },
  }
}

///|
test "Cloud control snapshots decode canonical queue and receipt state" {
  let fixture = control_snapshot_fixture()
  guard decode_control_event("control_state", fixture) is Snapshot(snapshot) else {
    fail("expected initial control snapshot without a kind field")
  }
  assert_eq(snapshot.session_id, "session")
  assert_eq(snapshot.task_id, Some("task"))
  assert_eq(snapshot.seq, 3)
  assert_true(snapshot.data.status is Running)
  assert_eq(snapshot.data.active_task_id, Some("task"))
  assert_false(snapshot.data.paused)
  assert_true(
    snapshot.data.queue ==
    [{ id: "queued", content: @wire.Content([Text("next")]), }],
  )
  assert_true(
    snapshot.data.steers == [{ submission_id: "steered", status: Pending, }],
  )
  let fields = match fixture {
    Object(fields) => fields.copy()
    _ => fail("object fixture")
  }
  fields["kind"] = Json("queue_changed")
  assert_true(
    decode_control_event("queue_changed", Json(fields)) == Snapshot(snapshot),
  )
  assert_true(
    decode_control_event("message", Json(fields)) == Snapshot(snapshot),
  )
  let fresh : ControlSnapshot = @json.from_json({
    "session_id": "session",
    "task_id": null,
    "seq": 0,
    "data": {
      "active_task_id": null,
      "status": "idle",
      "paused": false,
      "queue": [],
      "steers": [],
      "future": 1,
    },
  })
  assert_eq(fresh.task_id, None)
  assert_eq(fresh.seq, 0)
  assert_true(fresh.data.status is Idle && !fresh.data.paused)
  let stopping : ControlRunStatus = @json.from_json(Json("stopping"))
  assert_true(stopping is Stopping)
  for
    (status, expected) in [
      ("pending", Pending),
      ("applied", Applied),
      ("dropped", Dropped),
      ("unknown", Unknown),
    ] {
    let parsed : SteerStatus = @json.from_json(Json(status))
    assert_true(parsed == expected)
  }
}

///|
test "Cloud control snapshots reject absent null and malformed required fields" {
  let fixture = control_snapshot_fixture()
  guard fixture is Object(fields) else { fail("object fixture") }
  let invalid : Array[Json] = [null, Json("invalid"), {}]
  for key in ["session_id", "task_id", "seq", "data"] {
    let missing = fields.copy()
    ignore(missing.remove(key))
    invalid.push(Json(missing))
    if key != "task_id" {
      let wrong = fields.copy()
      wrong[key] = null
      invalid.push(Json(wrong))
    }
  }
  for seq in [-1.0, 0.5, 2147483648.0] {
    let wrong = fields.copy()
    wrong["seq"] = Json(seq)
    invalid.push(Json(wrong.copy()))
  }
  guard fields["data"] is Object(data) else { fail("state fixture") }
  for key in ["active_task_id", "status", "paused", "queue", "steers"] {
    let missing = data.copy()
    ignore(missing.remove(key))
    let wrong = fields.copy()
    wrong["data"] = Json(missing)
    invalid.push(Json(wrong.copy()))
    let null_field = data.copy()
    null_field[key] = null
    if key != "active_task_id" {
      wrong["data"] = Json(null_field)
      invalid.push(Json(wrong.copy()))
    }
  }
  for
    invalid_state in [
      ("status", Json("complete")),
      ("paused", Json("false")),
      ("active_task_id", Json(1)),
      ("queue", ([{ "id": "q", "content": null }] : Json)),
      ("queue", ([{ "content": "missing id" }] : Json)),
      ("steers", ([{ "submission_id": "s", "status": "rejected" }] : Json)),
    ] {
    let wrong_data = data.copy()
    wrong_data[invalid_state.0] = invalid_state.1
    let wrong = fields.copy()
    wrong["data"] = Json(wrong_data)
    invalid.push(Json(wrong))
  }
  for json in invalid {
    let rejected = try {
      ignore(decode_control_event("control_state", json))
      false
    } catch {
      @cloud_client.RequestError(Malformed) => true
      _ => false
    }
    assert_true(rejected)
  }
  let event = decode_control_event("task_started", {
    "session_id": "session",
    "task_id": "next-task",
    "seq": 4,
    "kind": "task_started",
    "data": { "submission_id": "q", "previous_task_id": "task" },
  })
  assert_true(event is EngineEvent({ task_id: "next-task", seq: 4, .. }))
  let invalid_event = try {
    ignore(
      decode_control_event("task_started", {
        "session_id": "session",
        "task_id": "task",
        "seq": 0,
        "kind": "task_started",
        "data": {},
      }),
    )
    false
  } catch {
    @cloud_client.RequestError(Malformed) => true
    _ => false
  }
  assert_true(invalid_event)
}

///|
extern "js" fn mock_control_http(
  status : Int32,
  response : String,
  record : (String, String, String, String) -> Unit,
) -> () -> Unit =
  #| (status, response, record) => {
  #|   const previous = globalThis.fetch;
  #|   globalThis.fetch = async (url, options) => {
  #|     const body = options.body == null ? "" : await new Response(options.body).text();
  #|     record(String(url), options.method, new Headers(options.headers).get("Authorization") || "", body);
  #|     if (status < 0) throw new TypeError("offline");
  #|     return new Response(response, {status});
  #|   };
  #|   return () => {globalThis.fetch = previous;};
  #| }

///|
async fn check_control_requests() -> Unit {
  let image = @wire.Image::from_base64(media_type="image/png", "iVBORw0KGgo=")
  let content = @wire.Content([Text("quoted text\n"), Image(image)])
  for
    (operation, endpoint, status, reply, expected) in [
      (
        Stop,
        "stop",
        202,
        ({ "accepted": true, "task_id": "task" } : Json),
        ({ "task_id": "task" } : Json),
      ),
      (
        Steer(submission_id="s", content~),
        "steer",
        202,
        { "accepted": true, "task_id": "task", "submission_id": "s" },
        {
          "task_id": "task",
          "submission_id": "s",
          "content": content.to_json(),
        },
      ),
      (
        QueueAdd(id="q", content~),
        "queue",
        200,
        { "accepted": true, "task_id": "task", "action": "add", "id": "q" },
        {
          "task_id": "task",
          "action": "add",
          "id": "q",
          "content": content.to_json(),
        },
      ),
      (
        QueueEdit(id="q", content~),
        "queue",
        200,
        { "accepted": true, "task_id": "task", "action": "edit", "id": "q" },
        {
          "task_id": "task",
          "action": "edit",
          "id": "q",
          "content": content.to_json(),
        },
      ),
      (
        QueueWithdraw(id="q"),
        "queue",
        200,
        { "accepted": true, "task_id": "task", "action": "withdraw", "id": "q" },
        { "task_id": "task", "action": "withdraw", "id": "q" },
      ),
      (
        QueueSteer(id="q"),
        "queue",
        200,
        { "accepted": true, "task_id": "task", "action": "steer", "id": "q" },
        { "task_id": "task", "action": "steer", "id": "q" },
      ),
    ] {
    let requests = []
    let restore = mock_control_http(status, reply.stringify(), (
      url,
      method_,
      auth,
      body,
    ) => requests.push((url, method_, auth, body)))
    defer restore()
    assert_true(control("fixture", "session/?", "task", operation) is Accepted)
    assert_eq(requests.length(), 1)
    let (url, method_, auth, body) = requests[0]
    assert_eq(url, CloudOrigin + "/v1/sessions/session%2F%3F/" + endpoint)
    assert_eq(method_, "POST")
    assert_eq(auth, "Bearer fixture")
    assert_eq(@json.parse(body), expected)
  }
}

///|
async fn check_control_failures() -> Unit {
  for
    (status, body, expected) in [
      (
        409,
        "{\"accepted\":false,\"error\":\"task_not_running\",\"task_id\":\"task\"}",
        Some(Rejected("task_not_running")),
      ),
      (202, "{\"accepted\":true,\"task_id\":\"task\"}", Some(Accepted)),
      (202, "{\"accepted\":true,\"task_id\":\"other-task\"}", None),
      (202, "{\"accepted\":false,\"task_id\":\"task\"}", None),
      (409, "{}", None),
      (
        409,
        "{\"accepted\":false,\"error\":\"closed\",\"task_id\":\"other\"}",
        None,
      ),
      (202, "not JSON", None),
      (401, "{}", None),
      (500, "{}", None),
      (-1, "", None),
    ] {
    let restore = mock_control_http(status, body, (_, _, _, _) => ())
    defer restore()
    try control("fixture", "session", "task", Stop) catch {
      @cloud_client.RequestError(failure) => {
        assert_true(expected is None)
        assert_true(
          match (status, failure) {
            (401, Unauthorized) | (500, Http(500)) | (-1, Unreachable) => true
            (_, Malformed) => status is (202 | 409)
            _ => false
          },
        )
      }
      error => fail("unexpected control error: \{error}")
    } noraise {
      result => assert_true(Some(result) == expected)
    }
  }
  for
    (operation, status, reply) in [
      (
        Steer(submission_id="s", content=@wire.Content([Text("hello")])),
        202,
        (
          { "accepted": true, "task_id": "task", "submission_id": "other" } :
          Json),
      ),
      (
        QueueWithdraw(id="q"),
        200,
        {
          "accepted": true,
          "task_id": "task",
          "action": "withdraw",
          "id": "other",
        },
      ),
      (
        QueueSteer(id="q"),
        200,
        { "accepted": true, "task_id": "task", "action": "withdraw", "id": "q" },
      ),
    ] {
    let restore = mock_control_http(status, reply.stringify(), (_, _, _, _) => {
      ()
    })
    defer restore()
    let malformed = try {
      ignore(control("fixture", "session", "task", operation))
      false
    } catch {
      @cloud_client.RequestError(Malformed) => true
      _ => false
    }
    assert_true(malformed)
  }
}

///|
async fn check_control_state_requests() -> Unit {
  let fixture = control_snapshot_fixture()
  let expected : ControlSnapshot = @json.from_json(fixture)
  {
    let requests = []
    let restore = mock_control_http(200, fixture.stringify(), (
      url,
      method_,
      auth,
      _,
    ) => requests.push((url, method_, auth)))
    defer restore()
    assert_true(read_control("fixture", "session") == expected)
    assert_eq(requests, [
      (CloudOrigin + "/v1/sessions/session/control", "GET", "Bearer fixture"),
    ])
    let rejected = try {
      ignore(read_control("fixture", "other"))
      false
    } catch {
      @cloud_client.RequestError(Malformed) => true
      _ => false
    }
    assert_true(rejected)
  }
  let body = "event: control_state\ndata: " +
    fixture.stringify() +
    "\n\nevent: task_finished\ndata: {\"session_id\":\"session\",\"task_id\":\"task\",\"seq\":4,\"kind\":\"task_finished\",\"data\":{}}\n\n"
  let requests = []
  let restore = mock_control_http(200, body, (url, method_, auth, _) => {
    requests.push((url, method_, auth))
  })
  defer restore()
  let stream = StreamLease::new()
  let events = []
  watch_control("fixture", "session", stream, event => events.push(event))
  assert_true(
    events is [Snapshot(snapshot), EngineEvent({ kind: "task_finished", .. })] &&
    snapshot == expected,
  )
  assert_eq(requests, [
    (CloudOrigin + "/v1/sessions/session/events", "GET", "Bearer fixture"),
  ])
  assert_true(stream.active)
  stream.close()
  let wrong_session = StreamLease::new()
  defer wrong_session.close()
  let wrong_events = []
  let rejected = try {
    watch_control("fixture", "other", wrong_session, event => {
      wrong_events.push(event)
    })
    false
  } catch {
    @cloud_client.RequestError(Malformed) => true
    _ => false
  }
  assert_true(rejected)
  assert_true(wrong_events.is_empty())
  let ignored = StreamLease::new()
  ignored.close()
  watch_control("fixture", "session", ignored, event => events.push(event))
  assert_eq(requests.length(), 2)
}

///|
async test "Cloud control HTTP and SSE preserve operation and ownership contracts" {
  // All fetch substitutions stay sequential within one async test.
  check_control_requests()
  check_control_failures()
  check_control_state_requests()
}
