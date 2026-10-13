///|
test "attachment sources preserve local paths and uploaded bytes" {
  for
    source in [
      @protocol.AttachmentPath("/Downloads/下载-5-1.pdf"),
      AttachmentBytes(name="report.docx", data_base64="UEs="),
    ] {
    let payload : @protocol.PrepareAttachmentPayload = {
      session: "session-1",
      workspace: "/workspace",
      source,
    }
    let decoded : @protocol.PrepareAttachmentPayload = @json.from_json(
      payload.to_json(),
    )
    assert_eq(decoded, payload)
  }
  let staging : @protocol.StageAttachmentsPayload = {
    session: "session-1",
    workspace: "/workspace/worktree",
    source_root: "/workspace",
    paths: [".openseek/attachments/id/report.pdf"],
  }
  let decoded : @protocol.StageAttachmentsPayload = @json.from_json(
    staging.to_json(),
  )
  assert_eq(decoded, staging)
}

///|
test "attachment preparation requires the fields consumed by each variant" {
  for
    json in (
      [
        { "kind": "path", "path": null },
        { "kind": "bytes", "name": "report.pdf" },
        { "kind": "bytes", "name": 7, "data_base64": "UEs=" },
        { "kind": "unknown" },
      ] : Array[Json]) {
    let source : @protocol.AttachmentSource? = Some(@json.from_json(json)) catch {
      _ => None
    }
    assert_true(source is None)
  }
  for
    json in (
      [
        { "kind": "reference", "path": null },
        { "kind": "upload_required" },
        { "kind": "image", "name": "picture.png", "url": false },
        { "kind": "unknown" },
      ] : Array[Json]) {
    let reply : @protocol.PrepareAttachmentReply? = Some(@json.from_json(json)) catch {
      _ => None
    }
    assert_true(reply is None)
  }
}

///|
test "cancelled native pickers omit their optional path and reject malformed values" {
  for json in [Json::object(Map([])), { "path": null }] {
    let reply : @protocol.PickAttachmentReply = @json.from_json(json)
    assert_eq(reply.path, None)
    @debug.assert_eq(reply.to_json(), Json::object(Map([])))
  }
  let reply : @protocol.PickAttachmentReply? = Some(
    @json.from_json({ "path": 42 }),
  ) catch {
    _ => None
  }
  assert_true(reply is None)
}
