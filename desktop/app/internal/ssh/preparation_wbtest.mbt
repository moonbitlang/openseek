///|
fn preparation_request() -> @protocol.SshPreparationRequest {
  {
    target: New(name="QA", destination="qa-host", data_dir="/qa/data"),
    directory: "/qa/package",
  }
}

///|
async test "cancelled reservation cannot execute and stale cancellation cannot cancel its replacement" {
  let manager = Preparation()
  let old = manager.begin(preparation_request())
  manager.cancel(old)
  let current = manager.begin(preparation_request())
  manager.cancel(old)
  assert_true(manager.progress(current).stage is Some(_))
  let calls = Ref(0)
  try {
    ignore(
      manager.execute(old, (_, _) => {
        calls.val += 1
        fail("old preparation executed")
      }),
    )
    fail("cancelled reservation accepted")
  } catch {
    SshError(_) => ()
    error => raise error
  }
  assert_eq(calls.val, 0)
  manager.close()
  assert_eq(manager.progress(current).stage, None)
}

///|
async test "window close joins preparation cleanup before accepting a replacement" {
  @async.with_timeout(10000, () => {
    let manager = Preparation()
    let token = manager.begin(preparation_request())
    let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let cleaning : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let cleaned = Ref(false)
    @async.with_task_group(group => {
      let operation = group.spawn(allow_failure=true, () => {
        manager.execute(token, (_, progress) => {
          defer @async.protect_from_cancel(() => {
            cleaning.put(())
            release.get()
            cleaned.val = true
          })
          progress("upload")
          entered.put(())
          @async.sleep(60000)
          fail("preparation was not cancelled")
        })
      })
      entered.get()
      assert_eq(manager.progress(token).stage, Some("upload"))
      let closed = group.spawn(() => manager.close())
      cleaning.get()
      assert_true(!cleaned.val)
      try {
        ignore(manager.begin(preparation_request()))
        fail("accepted replacement before cleanup")
      } catch {
        SshError(_) => ()
        error => raise error
      }
      release.put(())
      closed.wait()
      ignore(operation.wait()) catch {
        _ => ()
      }
      assert_true(cleaned.val)
      let replacement = manager.begin(preparation_request())
      assert_not_eq(replacement.id, token.id)
      manager.close()
    })
  })
}
