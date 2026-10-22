///|
/// A stand-in relay control endpoint: it accepts one registration, answers
/// `registered`, and hands every later text frame to `frames`.
async fn fake_control(
  server : @http.Server,
  frames : @async.Queue[String],
) -> Unit {
  let (conn, _) = server.accept()
  defer conn.close()
  let request = conn.read_request()
  let ws = @websocket.from_http_server(request, conn)
  defer ws.close()
  guard @tunnel.Frame::decode(ws.recv().read_all().text()) is Some(Register(..)) else {
    fail("expected a register frame")
  }
  ws.send_text((Registered(device="d_1") : @tunnel.Frame).encode())
  for ;; {
    frames.put(ws.recv().read_all().text())
  }
}

///|
async test "a registered connector tells the relay about a settled run" {
  let root = @fs.tmpdir(prefix="openseek-connector-push-")
  defer @fs.rmdir(root, recursive=true)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let frames : @async.Queue[String] = Queue(kind=Unbounded)
  let registered : @async.Queue[String] = Queue(kind=Unbounded)
  let actor = RelayActor(state, announce=device => {
    ignore(registered.try_put(device) catch { _ => false })
  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => fake_control(server, frames))
    group.spawn_bg(no_wait=true, () => {
      actor.connect_once({
        relay_url: "ws://127.0.0.1:\{server.addr.port()}/v1/tunnel",
        device_token: "odt_test",
        device_name: "Test Mac",
      })
    })
    assert_eq(registered.get(), "d_1")
    state.publish(
      AgentStarted({
        run_id: "r1",
        submission_id: None,
        engine: None,
        model: None,
        max_steps: None,
        session: "s1",
        session_root: None,
      }),
    )
    state.publish(
      AgentFinished({
        run_id: "r1",
        status: "finished",
        answer: Some("Done."),
        exit_code: None,
      }),
    )
    guard @async.with_timeout_opt(5_000, () => frames.get()) is Some(text) else {
      fail("the relay received no notify frame")
    }
    assert_true(
      @tunnel.Frame::decode(text)
      is Some(
        Notify(Finished(session="s1", status="finished", answer=Some("Done.")))
      ),
    )
  })
}
