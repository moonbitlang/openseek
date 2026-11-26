///|
async test "Cloud history survives a host restart and follows account retirement" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-cloud-cache-"))
  defer @fs.remove(root.to_string(), recursive=true)
  let first = sample_session(avatar="")
  let store = AuthStore::load(runtime_dir=root)
  store.commit_session(first)
  let page : @protocol.CloudHistoryCachePage = {
    session: {
      version: None,
      id: None,
      system_prompt: None,
      events: Some([
        {
          sequence: 7,
          ts: None,
          item: User({
            content: Content([Text("Cached chat\nSecond line")]),
            submission_id: None,
          }),
        },
      ]),
    },
    messages: [{ "kind": "user", "engine_sequence": 7, "data": {} }],
    prediction: None,
    offset: Some(3),
    etag: Some("etag-1"),
  }
  let write : @protocol.CloudHistoryCacheRequest = {
    token: first.account.token,
    action: Write(session="chat-a", view=Detail, page~),
  }
  assert_true(store.cloud_history_cache(write) is Done)
  let reopened = AuthStore::load(runtime_dir=root)
  let read = { ..write, action: Read(session="chat-a", view=Detail), }
  assert_true(
    reopened.cloud_history_cache(read)
    is Page(Some({ etag: Some("etag-1"), offset: Some(3), .. })),
  )
  let minimal_read = { ..read, action: Read(session="chat-a", view=Minimal), }
  assert_true(reopened.cloud_history_cache(minimal_read) is Page(None))
  ignore(
    reopened.cloud_history_cache({
      ..write,
      action: Write(session="chat-a", view=Minimal, page={
        ..page,
        etag: Some("minimal"),
      }),
    }),
  )
  assert_true(
    reopened.cloud_history_cache(minimal_read)
    is Page(Some({ etag: Some("minimal"), .. })),
  )
  assert_true(
    reopened.cloud_history_cache(read)
    is Page(Some({ etag: Some("etag-1"), .. })),
  )
  // Listing still finds the saved title even if neither page can be decoded.
  let cache_dir = root.join("cloud-history-cache").join("123")
  for dir in [cache_dir, cache_dir.join("minimal")] {
    @fsx.write_text(dir.join("chat-a.json"), "invalid page")
  }
  // Pre-catalog pages remain selectable by ID without opening their bodies.
  @fsx.write_text(cache_dir.join("legacy.json"), "invalid legacy page")
  let entries = reopened.cloud_history_cache({ ..write, action: List, })
  guard entries is Entries(rows) else { fail("missing catalog") }
  assert_true(rows.any(row => row.session == "legacy" && row.label == "legacy"))
  ignore(
    reopened.cloud_history_cache({ ..write, action: Remove(session="legacy"), }),
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
  assert_true(reopened.cloud_history_cache(minimal_read) is Page(None))
  assert_true(
    reopened.cloud_history_cache({
      ..write,
      action: Write(session="chat-b", view=Detail, page~),
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
      action: Write(session="late", view=Detail, page~),
    })
    is Done,
  )
  assert_true(
    reopened.cloud_history_cache({ token: second.account.token, action: List, })
    is Entries([]),
  )
  assert_eq(@fs.readdir(cache_dir.join("minimal").to_string()), [])
  assert_eq(
    @fs.readdir(cache_dir.to_string()).filter(name => name.has_suffix(".json")),
    ["chat-b.json"],
  )
  reopened.commit_session(first)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  reopened.session = Some({
    ..first,
    server_url: "http://127.0.0.1:\{server.local_addr().port}",
    device: None,
  })
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let sign_out = group.spawn(() => reopened.sign_out())
      let conn = server.accept()
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
