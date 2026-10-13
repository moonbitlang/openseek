///|
async fn attachment_test_workspace(session : String) -> @pathx.Absolute {
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-attachments-")),
  ).resolve()
  @work_dir.authorize_host_workspace(session, root.to_string())
  root
}

///|
async test "workspace documents become references without creating an upload" {
  let session = "attachment-inside"
  let root = attachment_test_workspace(session)
  defer @fs.rmdir(root.to_string(), recursive=true)
  defer @work_dir.revoke_host_workspace(session)
  let bytes = b"%PDF-1.7\noriginal document"
  let source = root.join("report.pdf")
  @fs.write_file(source.to_string(), bytes)
  let payload : @protocol.PrepareAttachmentPayload = {
    session,
    workspace: root.resource_path(),
    source: AttachmentPath(source.resource_path()),
  }
  assert_eq(
    prepare_attachment_op(payload),
    WorkspaceAttachment(path="report.pdf"),
  )
  assert_eq(import_attachment_op(payload).path, "report.pdf")
  assert_false(@fs.exists(root.join(".openseek").to_string()))
  assert_eq(@fs.read_file(source.to_string()).binary(), bytes)
}

///|
async test "external imports require preparation and preserve original bytes and names" {
  let session = "attachment-outside"
  let root = attachment_test_workspace(session)
  let outside = @fs.tmpdir(prefix="openseek-attachment-original-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  defer @fs.rmdir(outside, recursive=true)
  defer @work_dir.revoke_host_workspace(session)
  let original = "\{outside}/下载-5-1.pdf"
  let bytes = b"%PDF-1.7\noriginal bytes"
  @fs.write_file(original, bytes)
  let payload : @protocol.PrepareAttachmentPayload = {
    session,
    workspace: root.resource_path(),
    source: AttachmentPath(original),
  }
  assert_eq(
    prepare_attachment_op(payload),
    AttachmentUploadRequired(name="下载-5-1.pdf"),
  )
  assert_false(@fs.exists(root.join(".openseek").to_string()))
  let first = import_attachment_op(payload)
  let second = import_attachment_op(payload)
  assert_true(first.path != second.path)
  assert_true(first.path.has_suffix("/下载-5-1.pdf"))
  for imported in [first, second] {
    let file = root.join((imported.path : @pathx.Relative))
    assert_eq(@fs.read_file(file.to_string()).binary(), bytes)
    assert_eq(@fs.readdir(file.to_path().dirname().to_string()), [
      "下载-5-1.pdf",
    ])
  }
  assert_eq(@fs.read_file(original).binary(), bytes)
}

///|
async test "browser document bytes import one original file and reject traversal" {
  let session = "attachment-browser"
  let root = attachment_test_workspace(session)
  defer @fs.rmdir(root.to_string(), recursive=true)
  defer @work_dir.revoke_host_workspace(session)
  let bytes = b"PK office bytes"
  for name in ["Report.DOCX", "table.xlsx"] {
    let payload : @protocol.PrepareAttachmentPayload = {
      session,
      workspace: root.resource_path(),
      source: AttachmentBytes(name~, data_base64=@base64.encode(bytes)),
    }
    assert_eq(prepare_attachment_op(payload), AttachmentUploadRequired(name~))
    assert_eq(
      @fs.read_file(
        root
        .join((import_attachment_op(payload).path : @pathx.Relative))
        .to_string(),
      ).binary(),
      bytes,
    )
  }
  let rejected = try {
    ignore(
      import_attachment_op({
        session,
        workspace: root.resource_path(),
        source: AttachmentBytes(
          name="../outside.pdf",
          data_base64=@base64.encode(bytes),
        ),
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
async test "attachment imports reject escaping directory links before writing" {
  let session = "attachment-link"
  let root = attachment_test_workspace(session)
  let outside = @fs.tmpdir(prefix="openseek-attachment-link-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  defer @fs.rmdir(outside, recursive=true)
  defer @work_dir.revoke_host_workspace(session)
  @fs.symlink(target=outside, root.join(".openseek").to_string())
  let rejected = try {
    ignore(
      import_attachment_op({
        session,
        workspace: root.resource_path(),
        source: AttachmentBytes(
          name="report.pdf",
          data_base64=@base64.encode(b"%PDF-original"),
        ),
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(@fs.readdir(outside).is_empty())
}

///|
async test "attachment preparation rejects unavailable workspace empty and oversized files" {
  let session = "attachment-limits"
  let root = attachment_test_workspace(session)
  defer @fs.rmdir(root.to_string(), recursive=true)
  defer @work_dir.revoke_host_workspace(session)
  let unknown = try {
    ignore(
      prepare_attachment_op({
        session: "attachment-unbound",
        workspace: root.resource_path(),
        source: AttachmentBytes(name="report.pdf", data_base64="JVBERg=="),
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(unknown)
  for bytes in [b"", Bytes::make(@openpath.MaxOfficeFileBytes + 1, b'0')] {
    let rejected = try {
      ignore(
        prepare_attachment_op({
          session,
          workspace: root.resource_path(),
          source: AttachmentBytes(
            name="report.pdf",
            data_base64=@base64.encode(bytes),
          ),
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_false(@fs.exists(root.join(".openseek").to_string()))
}

///|
async test "imported originals reach a newly bound worktree and remain available on retry" {
  let session = "attachment-worktree"
  let source = attachment_test_workspace(session)
  let checkout = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-attachment-worktree-")),
  ).resolve()
  defer @fs.rmdir(source.to_string(), recursive=true)
  defer @fs.rmdir(checkout.to_string(), recursive=true)
  defer @work_dir.revoke_host_workspace(session)
  let bytes = b"%PDF-worktree original"
  let imported = import_attachment_op({
    session,
    workspace: source.resource_path(),
    source: AttachmentBytes(
      name="report.pdf",
      data_base64=@base64.encode(bytes),
    ),
  })
  @work_dir.authorize_host_workspace(session, checkout.to_string())
  let payload : @protocol.StageAttachmentsPayload = {
    session,
    workspace: checkout.resource_path(),
    source_root: source.resource_path(),
    paths: [imported.path],
  }
  ignore(stage_attachments_op(payload))
  let target = checkout.join((imported.path : @pathx.Relative))
  assert_eq(@fs.read_file(target.to_string()).binary(), bytes)
  assert_eq(@fs.readdir(target.to_path().dirname().to_string()), ["report.pdf"])
  assert_eq(
    @fs.read_file(source.join((imported.path : @pathx.Relative)).to_string()).binary(),
    bytes,
  )
  // A user's later edit is retained when the same pending message is retried.
  @fs.write_file(target.to_string(), b"%PDF-user edit")
  ignore(stage_attachments_op(payload))
  assert_eq(@fs.read_file(target.to_string()).binary(), b"%PDF-user edit")
}

///|
async test "attachment staging rejects non-imported paths and escaping source links" {
  let session = "attachment-stage-link"
  let root = attachment_test_workspace(session)
  let source = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-attachment-stage-source-")),
  ).resolve()
  let outside = @fs.tmpdir(prefix="openseek-attachment-stage-link-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  defer @fs.rmdir(source.to_string(), recursive=true)
  defer @fs.rmdir(outside, recursive=true)
  defer @work_dir.revoke_host_workspace(session)
  @fs.mkdir(source.join(".openseek/attachments/id").to_string(), recursive=true)
  @fs.write_file("\{outside}/report.pdf", b"%PDF-outside")
  @fs.symlink(
    target="\{outside}/report.pdf",
    source.join(".openseek/attachments/id/report.pdf").to_string(),
  )
  for
    path in [
      "report.pdf", ".openseek/attachments/../report.pdf", ".openseek/attachments/id/report.pdf",
    ] {
    let rejected = try {
      ignore(
        stage_attachments_op({
          session,
          workspace: root.resource_path(),
          source_root: source.resource_path(),
          paths: [path],
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_false(@fs.exists(root.join(".openseek").to_string()))
}
