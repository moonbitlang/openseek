///|
/// Encode app-server's native paths on the owning host, using the same
/// reversible resource-path convention as the rest of the Desktop protocol.
fn codex_resource_path(path : String) -> String raise @host.HostError {
  guard @pathx.Path(path).to_absolute().bind(path => path.to_uri_path())
    is Some(resource) else {
    raise HostError("unsupported Codex workspace path: " + path)
  }
  resource
}

///|
fn codex_same_workspace(left : String, right : String) -> Bool {
  @pathx.Absolute::from_uri_path(left) is Some(path) &&
  @pathx.Absolute::from_uri_path(right) is Some(root) &&
  path.relative_to(root~) is Some(relative) &&
  relative.is_root()
}

///|
async test "Codex thread resources roundtrip through host workspace grants" {
  let native = if @platform.win32 || @platform.win64 {
    "C:\\work\\project"
  } else {
    "/work/project"
  }
  let resource = if @platform.win32 || @platform.win64 {
    "/c:/work/project"
  } else {
    "/work/project"
  }
  let frontend = if @platform.win32 || @platform.win64 {
    "/C:/work/project"
  } else {
    resource
  }
  let thread : Json = {
    "id": "codex-path-roundtrip",
    "cwd": native,
    "projectRoot": native,
  }
  let catalog = CodexWorktreeCatalog([])
  let reply = catalog.annotate({ "thread": thread })
  assert_eq(reply, {
    "thread": {
      "id": "codex-path-roundtrip",
      "cwd": resource,
      "projectRoot": resource,
    },
  })
  assert_eq(catalog.annotate({ "data": [thread] }), {
    "data": [
      { "id": "codex-path-roundtrip", "cwd": resource, "projectRoot": resource },
    ],
  })
  assert_true(codex_same_workspace(resource, frontend))
  assert_true(!codex_same_workspace(resource, frontend + "/child"))
  guard CodexWorkspaceBinding::decode_reply(reply) is Some(binding) else {
    fail("expected a thread workspace binding")
  }
  defer @work_dir.revoke_host_workspace(binding.session)
  binding.authorize()
  guard @work_dir.resolve_host_workspace_authorization(
      binding.session,
      frontend,
    )
    is Some(authorized) else {
    fail("expected the frontend resource to resolve to the native cwd")
  }
  guard @pathx.Path(native).to_absolute() is Some(root) else {
    fail("expected a native absolute path")
  }
  assert_true(
    authorized.relative_to(root~) is Some(relative) && relative.is_root(),
  )
}
