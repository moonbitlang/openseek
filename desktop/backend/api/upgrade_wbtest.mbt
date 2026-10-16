///|
async test "idle upgrade atomically blocks admission while busy and recovery preserve state" {
  let service = test_service()
  let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => service.admission.run())
      let work = group.spawn(() => {
        service.admission.invoke("workspace.add", {}, () => {
          entered.put(())
          release.get()
          Json::null()
        })
      })
      entered.get()
      assert_false(service.try_upgrade())
      assert_eq(service.status(), "ready")
      release.put(())
      ignore(work.wait())
      assert_true(service.try_upgrade())
      assert_eq(service.status(), "draining")
      let invoked = Ref(false)
      try
        service.admission.invoke("workspace.add", {}, () => {
          invoked.val = true
          Json::null()
        })
      catch {
        @lifecycle.AdmissionError(_) => ()
        error => raise error
      } noraise {
        _ => fail("new mutation must not cross the upgrade barrier")
      }
      assert_false(invoked.val)
      assert_false(service.try_upgrade())
    })
  })
  let recovery = test_service()
  recovery.require_recovery()
  assert_false(recovery.try_upgrade())
  assert_eq(recovery.status(), "recovery_required")
}

///|
async test "uncertain disconnected login cleanup remains busy until cancellation is confirmed" {
  let fail_cancel = Ref(true)
  let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let scope = ClientLoginScope(_ => {
    if fail_cancel.val {
      entered.put(())
      release.get()
      raise @host.HostError("cancel not confirmed")
    }
  })
  let service = test_service()
  service.upgrade_activity[0] = () => scope.has_active_work()
  ignore(
    scope.invoke("codex.account.login.start", {}, () => { "loginId": "pending" }),
  )
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let closing = group.spawn(() => {
        try scope.close() catch {
          @host.HostError(_) => ()
          error => raise error
        } noraise {
          _ => fail("fixture cancellation must fail")
        }
      })
      entered.get()
      assert_false(service.try_upgrade())
      release.put(())
      closing.wait()
      assert_false(service.try_upgrade())
      assert_eq(service.status(), "ready")
    })
  })
  fail_cancel.val = false
  scope.close()
  assert_true(service.try_upgrade())
}
