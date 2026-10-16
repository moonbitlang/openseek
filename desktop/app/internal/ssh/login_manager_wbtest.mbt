///|
fn[G] login_test_manager(
  group : @async.TaskGroup[G],
  directory : String,
  request : async (Int32, String, Json) -> Json,
  tunnel~ : async (async () -> Unit) -> Unit = body => body(),
  abort~ : (Int32) -> Unit = _ => (),
  notify~ : async (Int32, String, String) -> Unit = (_, _, _) => (),
) -> LoginManager {
  LoginManager(
    directory~,
    spawn=body => group.spawn(body, allow_failure=true),
    request~,
    tunnel~,
    abort_connection=abort,
    notify_failure=notify,
  )
}

///|
fn login_completion(id : String) -> Json {
  {
    "method": "codex.notification",
    "params": {
      "method": "account/login/completed",
      "params": { "loginId": id },
    },
  }
}

///|
async test "failed remote cancellation removes the browser flow and releases the callback lease" {
  let directory = @fs.tmpdir(prefix="ssh-login-cancel-failed-")
  defer @fs.rmdir(directory, recursive=true)
  let notices : Array[String] = []
  let closed = Ref(0)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let manager = login_test_manager(
        group,
        directory,
        (_, method_, _) => {
          if method_ == @commands.codex_account_login_start.name() {
            { "loginId": "failed", "authUrl": "https://example.test/login" }
          } else {
            { "error": "remote cancellation refused" }
          }
        },
        tunnel=body => {
          defer {
            closed.val += 1
          }
          body()
        },
        notify=(_, id, message) => {
          assert_eq(id, "failed")
          notices.push(message)
        },
      )
      ignore(manager.start(1, {}))
      assert_eq(manager.cancel(1, "failed"), {
        "error": "remote cancellation refused",
      })
      assert_eq(notices, ["remote cancellation refused"])
      assert_eq(closed.val, 1)
      assert_true(manager.active is None)
      ignore(manager.start(1, {}))
      manager.close()
      assert_eq(closed.val, 2)
    })
  })
}

///|
async test "SSH login managers arbitrate the callback lease before remote login" {
  let directory = @fs.tmpdir(prefix="ssh-login-lease-")
  defer @fs.rmdir(directory, recursive=true)
  let starts = Ref(0)
  let cancelled : Array[String] = []
  let request : async (Int32, String, Json) -> Json = (_epoch, method_, params) => {
    if method_ == @commands.codex_account_login_start.name() {
      starts.val += 1
      {
        "loginId": "login-\{starts.val}",
        "authUrl": "https://example.test/login",
      }
    } else {
      guard params is { "loginId": String(id), .. } else {
        fail("missing login ID")
      }
      cancelled.push(id)
      Json::empty_object()
    }
  }
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let first = login_test_manager(group, directory, request)
      let other = login_test_manager(group, directory, request)
      ignore(first.start(1, {}))
      try other.start(1, {}) catch {
        SshError(message) =>
          assert_true(message.contains("Another SSH browser login"))
        error => raise error
      } noraise {
        _ => fail("second window acquired occupied callback")
      }
      assert_eq(starts.val, 1)
      ignore(first.cancel(1, "login-1"))
      assert_eq(cancelled, ["login-1"])
      ignore(other.start(1, {}))
      assert_eq(starts.val, 2)
      other.close()
      first.close()
      assert_eq(cancelled, ["login-1", "login-2"])
    })
  })
}

///|
async test "cancelled SSH login caller still cancels the late remote login without opening a browser" {
  let directory = @fs.tmpdir(prefix="ssh-login-late-")
  defer @fs.rmdir(directory, recursive=true)
  let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let cancelled : @async.Queue[String] = Queue(kind=Blocking(1))
  let opened = Ref(false)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let manager = login_test_manager(
        group,
        directory,
        (_, method_, params) => {
          if method_ == @commands.codex_account_login_start.name() {
            entered.put(())
            release.get()
            { "loginId": "late", "authUrl": "https://example.test/login" }
          } else {
            guard params is { "loginId": String(id), .. } else {
              fail("missing login ID")
            }
            cancelled.put(id)
            Json::empty_object()
          }
        },
        tunnel=body => {
          opened.val = true
          body()
        },
      )
      let caller = group.spawn(allow_failure=true, () => manager.start(7, {}))
      entered.get()
      caller.cancel()
      try caller.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      } noraise {
        _ => fail("caller should be cancelled")
      }
      release.put(())
      assert_eq(cancelled.get(), "late")
      manager.close()
      assert_false(opened.val)
    })
  })
}

///|
async test "late completion cannot release a new SSH login tunnel" {
  let directory = @fs.tmpdir(prefix="ssh-login-completed-")
  defer @fs.rmdir(directory, recursive=true)
  let starts = Ref(0)
  let closed = Ref(0)
  let cancelled : Array[String] = []
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let manager = login_test_manager(
        group,
        directory,
        (_, method_, params) => {
          if method_ == @commands.codex_account_login_start.name() {
            starts.val += 1
            {
              "loginId": "login-\{starts.val}",
              "authUrl": "https://example.test/login",
            }
          } else {
            guard params is { "loginId": String(id), .. } else {
              fail("missing login ID")
            }
            cancelled.push(id)
            Json::empty_object()
          }
        },
        tunnel=body => {
          defer {
            closed.val += 1
          }
          body()
        },
      )
      ignore(manager.start(2, {}))
      guard manager.active is Some(first) && first.task is Some(task) else {
        fail("missing owner")
      }
      manager.observe(1, login_completion("login-1"))
      manager.observe(2, login_completion("old"))
      assert_eq(closed.val, 0)
      manager.observe(2, login_completion("login-1"))
      task.wait()
      assert_eq(closed.val, 1)
      assert_eq(cancelled, [])
      ignore(manager.start(2, {}))
      manager.observe(2, login_completion("login-1"))
      try manager.cancel(2, "login-1") catch {
        SshError(_) => ()
        error => raise error
      } noraise {
        _ => fail("stale cancellation was accepted")
      }
      assert_eq(closed.val, 1)
      manager.close()
      assert_eq(closed.val, 2)
      assert_eq(cancelled, ["login-2"])
    })
  })
}

///|
async test "SSH tunnel startup and lifetime failures cancel the remote login" {
  for ready in [false, true] {
    let directory = @fs.tmpdir(prefix="ssh-login-failed-")
    defer @fs.rmdir(directory, recursive=true)
    let failed : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let notices : @async.Queue[String] = Queue(kind=Blocking(1))
    let cancelled : Array[String] = []
    @async.with_timeout(5000, () => {
      @async.with_task_group(group => {
        let manager = login_test_manager(
          group,
          directory,
          (_, method_, _) => {
            if method_ == @commands.codex_account_login_start.name() {
              { "loginId": "failed", "authUrl": "https://example.test/login" }
            } else {
              cancelled.push("failed")
              Json::empty_object()
            }
          },
          tunnel=body => {
            if ready {
              @async.any([
                body,
                () => {
                  failed.get()
                  raise SshError("tunnel expired")
                },
              ])
            } else {
              raise SshError("tunnel refused")
            }
          },
          notify=(_, id, message) => {
            assert_eq(id, "failed")
            notices.put(message)
          },
        )
        if ready {
          ignore(manager.start(1, {}))
          failed.put(())
          assert_true(notices.get().contains("expired"))
        } else {
          try manager.start(1, {}) catch {
            SshError(message) => assert_true(message.contains("refused"))
            error => raise error
          } noraise {
            _ => fail("URL returned before tunnel readiness")
          }
        }
        manager.close()
        assert_eq(cancelled, ["failed"])
      })
    })
  }
}
