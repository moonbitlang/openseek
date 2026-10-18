///|
test "import request codecs preserve source and optional worktree placement" {
  for worktree_of in [None, Some("source-session")] {
    for
      source in [
        @protocol.JsonFile(text="{}"),
        ShareLink(url="https://example/v1/shares/sh_test"),
      ] {
      let payload : @protocol.SessionImportPayload = {
        source,
        workspace: "/project",
        worktree_of,
      }
      let encoded = payload.to_json()
      let decoded : @protocol.SessionImportPayload = @json.from_json(encoded)
      assert_eq(decoded, payload)
      assert_true(
        match worktree_of {
          None => encoded is { "worktree_of": Null, .. }
          Some(_) => encoded is { "worktree_of": String("source-session"), .. }
        },
      )
    }
  }
  let invalid : Array[Json] = [
    { "source": { "kind": "unknown" }, "workspace": "/project" },
    { "source": { "kind": "share", "url": null }, "workspace": "/project" },
    {
      "source": { "kind": "share", "url": "https://example" },
      "workspace": "/project",
      "worktree_of": [],
    },
  ]
  for json in invalid {
    let refused = try {
      let _ : @protocol.SessionImportPayload = @json.from_json(json)
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "import reply carries the session id and preserves failure diagnostics" {
  let success : Json = { "status": "success", "session_id": "desktop-imported" }
  let reply : @protocol.SessionImportReply = @json.from_json(success)
  assert_true(reply is Success("desktop-imported"))
  assert_eq(reply.to_json(), success)
  let failure : Json = {
    "status": "failed",
    "message": "The share has expired.",
  }
  let reply : @protocol.SessionImportReply = @json.from_json(failure)
  assert_true(reply is Failed("The share has expired."))
  assert_eq(reply.to_json(), failure)
}
