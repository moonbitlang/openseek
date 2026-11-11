///|
#cfg(not(platform="windows"))
async test "Local preview tool uses its caller's workspace and only acknowledges opening" {
  home_env_test_lock.acquire()
  defer home_env_test_lock.release()
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="seekmoon-preview-tools-")),
  ).resolve()
  defer @fs.rmdir(root.to_string(), recursive=true)
  let previous = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.to_string())
  defer (match previous {
    Some(value) => @sys.set_env_var("HOME", value)
    None => @sys.unset_env_var("HOME")
  })
  let workspace = root.join("project")
  @fs.mkdir(workspace.to_string())
  ignore(@workspaces.add(workspace.to_string(), _ => ()))
  let dir = workspace.join(".openseek/sessions/caller")
  @fs.mkdir(dir.to_string(), recursive=true)
  @fs.write_text(
    dir.join("openseek_session-caller.jsonl").to_string(),
    "{\"version\":1,\"id\":\"caller\",\"system_prompt\":\"\"}\n",
  )
  let server = @mcp.Server([], version="test")
  let state = @api.ApiState(engine="unused", host_mcp=server)
  let requests : @async.Queue[@protocol.PreviewOpenRequest] = Queue(
    kind=Blocking(16),
  )
  let subscription = state.subscribe(
    requests,
    map=event => {
      match event {
        PreviewOpen(request) => Some(request)
        _ => None
      }
    },
    on_lag=sub => sub.close(),
  )
  defer subscription.close()
  @async.with_task_group(group => {
    state.start_services(group)
    let grant = server.grant("caller")
    let connection = @streamhttp.connect(
      group,
      url=server.url(),
      headers={
        "Authorization": "Bearer " + grant.get(@mcp.TokenEnv).unwrap(),
        "X-SeekMoon-Tool-Groups": "preview",
      },
      client_name="test",
      client_version="test",
    )
    defer connection.shutdown()
    let client = connection.client()
    assert_eq(client.list_tools().map(tool => tool.name), ["preview_open"])
    for
      path in [
        "index.html", "report.pdf", "image.png", "report.docx", "src/main.mbt", "notes.txt",
      ] {
      let result = client.call_tool(name="preview_open", arguments={
        "path": Json(path),
        "session": "other",
        "workspace": "/wrong",
      })
      assert_false(result.is_error)
      assert_true(
        @json.parse(result.render_text()) is { "status": "opening", .. },
      )
      assert_eq(
        requests.try_get(),
        Some(
          Local(session="caller", workspace=workspace.resource_path(), path~),
        ),
      )
    }
    for path in ["/tmp/a.html", "../a.html", "https://example.com"] {
      assert_true(
        client.call_tool(name="preview_open", arguments={ "path": Json(path) }).is_error,
      )
    }
    assert_true(requests.try_get() is None)
    group.return_immediately()
  })
}
