///|
async test "accepted mutation survives requester cancellation and drain rejects later work" {
  let admission = @lifecycle.Admission()
  let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let finish : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let settled : @async.Queue[Unit] = Queue(kind=Blocking(1))
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => admission.run())
      let request = group.spawn(allow_failure=true, () => {
        admission.invoke("workspace.add", Json::null(), () => {
          entered.put(())
          finish.get()
          settled.put(())
          Json::null()
        })
      })
      entered.get()
      request.cancel()
      admission.drain()
      assert_eq(admission.pending(), 1)
      let denied = try {
        ignore(
          admission.invoke("workspace.add", Json::null(), () => {
            fail("mutation after drain")
          }),
        )
        false
      } catch {
        @lifecycle.AdmissionError(_) => true
        error => raise error
      }
      assert_true(denied)
      assert_eq(
        admission.invoke("agent.runs", Json::null(), () => Json("query")),
        Json("query"),
      )
      for method_ in ["fs.resolve_reference", "fs.preview_content"] {
        assert_eq(
          admission.invoke(method_, Json::null(), () => Json("path")),
          Json("path"),
        )
      }
      assert_eq(
        admission.invoke("session.export_content", Json::null(), () => {
          Json("content")
        }),
        Json("content"),
      )
      assert_eq(
        admission.invoke("agent.approval", Json::null(), () => Json("approved")),
        Json("approved"),
      )
      assert_eq(
        admission.invoke("codex.account.login.cancel", Json::null(), () => {
          Json("cancelled")
        }),
        Json("cancelled"),
      )
      finish.put(())
      settled.get()
      // Wait for the service-owned task's accounting to settle, not a wall-clock delay.
      while admission.pending() > 0 {
        @async.pause()
      }
      assert_eq(admission.pending(), 0)
    })
  })
}

///|
test "recovery is fail closed even for queries that may migrate state" {
  let admission = @lifecycle.Admission()
  admission.require_recovery()
  for kind in [@lifecycle.Query, Connection, Control, Mutation] {
    let rejected = try {
      admission.check(kind)
      false
    } catch {
      @lifecycle.AdmissionError(_) => true
      error => raise error
    }
    assert_true(rejected)
  }
  assert_true(@lifecycle.request_kind("future.unknown") is Mutation)
}
