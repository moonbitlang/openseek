///|
async test "Cloud history survives a host restart and follows account retirement" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-cloud-cache-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let first = sample_session(avatar="")
  let store = AuthStore::load(runtime_dir=root)
  store.commit_session(first)
  let page : @protocol.CloudHistoryCachePage = {
    session: { version: None, id: None, system_prompt: None, events: Some([]), },
    messages: [
      { "kind": "user", "data": { "content": "Cached chat\nSecond line" } },
    ],
    offset: Some(3),
    etag: Some("etag-1"),
  }
  let write : @protocol.CloudHistoryCacheRequest = {
    token: first.account.token,
    action: Write(session="chat-a", page~),
  }
  assert_true(store.cloud_history_cache(write) is Done)
  let reopened = AuthStore::load(runtime_dir=root)
  let read = { ..write, action: Read(session="chat-a"), }
  assert_true(
    reopened.cloud_history_cache(read)
    is Page(Some({ etag: Some("etag-1"), offset: Some(3), .. })),
  )
  assert_true(
    reopened.cloud_history_cache({ ..write, action: List, })
    is Entries([{ session: "chat-a", label: "Cached chat", }]),
  )
  assert_true(
    reopened.cloud_history_cache({ ..write, action: Remove(session="chat-a"), })
    is Done,
  )
  assert_true(reopened.cloud_history_cache(write) is Done)
  assert_true(reopened.cloud_history_cache(read) is Page(None))
  assert_true(
    reopened.cloud_history_cache({
      ..write,
      action: Write(session="chat-b", page~),
    })
    is Done,
  )

  let second = {
    ..first,
    account: {
      token: "ts_other",
      user: { ..first.account.user, user_id: "456", },
    },
  }
  reopened.commit_session(second)
  assert_true(
    reopened.cloud_history_cache({
      ..write,
      action: Write(session="late", page~),
    })
    is Done,
  )
  assert_true(
    reopened.cloud_history_cache({ token: second.account.token, action: List, })
    is Entries([]),
  )
  assert_eq(
    @fs.readdir(root.join("cloud-history-cache").join("123").to_string()),
    ["chat-b.json"],
  )
  reopened.commit_session(first)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  reopened.session = Some({
    ..first,
    server_url: "http://127.0.0.1:\{server.addr.port()}",
    device: None,
  })
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let sign_out = group.spawn(() => reopened.sign_out())
      let (conn, _) = server.accept()
      defer conn.close()
      assert_eq(conn.read_request().path, "/v2/auth/logout")
      conn.skip_request_body()
      conn.send_response(204, "No Content")
      conn.end_response()
      sign_out.wait()
    })
  })
  assert_eq(@fs.readdir(root.join("cloud-history-cache").to_string()), [])
  assert_true(reopened.cloud_history_cache(write) is Done)
  assert_eq(@fs.readdir(root.join("cloud-history-cache").to_string()), [])
  assert_true(AuthStore::load(runtime_dir=root).account() is None)
}
