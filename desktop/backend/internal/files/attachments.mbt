///|
priv struct LoadedAttachment {
  name : String
  bytes : Bytes
  path : @pathx.Absolute?
}

///|
fn attachment_name_is_safe(name : String) -> Bool {
  !name.is_empty() &&
  name != "." &&
  name != ".." &&
  !name.contains_any(chars="/\\\u0000:")
}

///|
fn is_document_attachment(name : String) -> Bool {
  let name = name.to_lower()
  name.has_suffix(".pdf") ||
  name.has_suffix(".docx") ||
  name.has_suffix(".xlsx") ||
  name.has_suffix(".pptx")
}

///|
async fn attachment_workspace(
  session : String,
  workspace : String,
) -> @pathx.Absolute {
  guard @work_dir.resolve_in_workspace(session, ".", workspace~) is Some(root) else {
    raise InvalidRequest("this conversation has no accessible workspace")
  }
  @pathx.Path(@fs.realpath(root.to_string())).resolve()
}

///|
async fn load_attachment(
  source : @protocol.AttachmentSource,
) -> LoadedAttachment {
  let loaded = match source {
    AttachmentPath(path) => {
      let path = @pathx.Absolute::parse_resource_path(path)
      let path = @pathx.Path(@fs.realpath(path.to_string())).resolve()
      guard @fs.kind(path.to_string()) is Regular else {
        raise InvalidRequest("attachment must be a file")
      }
      let file = @fs.open(path.to_string(), mode=ReadOnly)
      defer file.close()
      let size = file.size()
      guard size <= MaxOfficeFileBytes.to_int64() else {
        raise InvalidRequest("documents must be 20 MiB or smaller")
      }
      {
        name: path.to_path().basename().to_owned(),
        bytes: file.read_exactly_at(size.to_int(), position=0),
        path: Some(path),
      }
    }
    AttachmentBytes(name~, data_base64~) => {
      guard data_base64.length() <= (MaxOfficeFileBytes + 2) / 3 * 4 else {
        raise InvalidRequest("documents must be 20 MiB or smaller")
      }
      let bytes = @base64.decode(data_base64) catch {
        _ => raise InvalidRequest("invalid attachment bytes")
      }
      { name, bytes, path: None, }
    }
  }
  guard attachment_name_is_safe(loaded.name) else {
    raise InvalidRequest("invalid attachment filename")
  }
  guard !loaded.bytes.is_empty() else {
    raise InvalidRequest("attachment is empty")
  }
  guard loaded.bytes.length() <= MaxOfficeFileBytes else {
    raise InvalidRequest("documents must be 20 MiB or smaller")
  }
  guard is_document_attachment(loaded.name) ||
    @filekind.classify(loaded.bytes) is Image(_) else {
    raise InvalidRequest(
      "choose PNG, JPEG, WebP, GIF, PDF, DOCX, XLSX or PPTX files",
    )
  }
  loaded
}

///|
pub async fn prepare_attachment(
  payload : @protocol.PrepareAttachmentPayload,
) -> @protocol.PrepareAttachmentReply {
  let root = attachment_workspace(payload.session, payload.workspace)
  let file = load_attachment(payload.source)
  if !is_document_attachment(file.name) &&
    @filekind.classify(file.bytes) is Image(media_type~) {
    guard file.bytes.length() <= @protocol.MaxImageBytes else {
      raise InvalidRequest(
        "each image must be \{@protocol.MaxImageBytes / 1024 / 1024} MiB or smaller",
      )
    }
    return AttachmentImage(
      name=file.name,
      url="data:\{media_type};base64,\{@base64.encode(file.bytes)}",
    )
  }
  if file.path is Some(path) && path.relative_to(root~) is Some(relative) {
    return WorkspaceAttachment(path=relative.to_string())
  }
  // Preparing never creates a directory or writes bytes. Only the explicit
  // Upload action invokes import_attachment.
  AttachmentUploadRequired(name=file.name)
}

///|
/// Resolve the nearest existing parent before creating missing directories.
/// Checking only a nonexistent final path would miss an escaping parent link.
async fn ensure_attachment_directory(
  root : @pathx.Absolute,
  directory : String,
) -> @pathx.Absolute {
  let target = root.join((directory : @pathx.Relative))
  let mut parent = target.to_path()
  while !@fs.exists(parent.to_string()) {
    let next = parent.dirname()
    guard next != parent else {
      raise InvalidRequest("attachment directory is unavailable")
    }
    parent = next
  }
  guard root.contains(@pathx.Path(@fs.realpath(parent.to_string())).resolve()) else {
    raise InvalidRequest("attachment directory escapes the workspace")
  }
  @fs.mkdir(target.to_string(), recursive=true, allow_exist=true)
  guard root.contains(@pathx.Path(@fs.realpath(target.to_string())).resolve()) else {
    raise InvalidRequest("attachment directory escapes the workspace")
  }
  target
}

///|
pub async fn import_attachment(
  payload : @protocol.PrepareAttachmentPayload,
) -> @protocol.ImportAttachmentReply {
  let root = attachment_workspace(payload.session, payload.workspace)
  let file = load_attachment(payload.source)
  guard is_document_attachment(file.name) else {
    raise InvalidRequest("only documents are imported into the workspace")
  }
  if file.path is Some(path) && path.relative_to(root~) is Some(relative) {
    return { path: relative.to_string(), }
  }
  let directory = ".openseek/attachments/\{@uuid.mint()}"
  // Check existing parents, including symlinks, before any workspace mutation.
  guard @work_dir.resolve_in_workspace(
      payload.session,
      directory,
      workspace=payload.workspace,
    )
    is Some(_) else {
    raise InvalidRequest("attachment directory escapes the workspace")
  }
  ignore(ensure_attachment_directory(root, directory))
  let relative = "\{directory}/\{file.name}"
  let target = root.join((relative : @pathx.Relative))
  @fs.write_binary(target.to_string(), file.bytes, create_mode=CreateNew)
  { path: relative, }
}

///|
/// First-send worktree creation changes the execution directory. Carry only
/// the message's imported originals into that checkout, retaining their
/// relative references. Existing originals make retries idempotent.
pub async fn stage_attachments(
  payload : @protocol.StageAttachmentsPayload,
) -> @protocol.EmptyReply {
  let root = attachment_workspace(payload.session, payload.workspace)
  let source_root = @pathx.Absolute::parse_resource_path(payload.source_root)
  let source_root = @pathx.Path(@fs.realpath(source_root.to_string())).resolve()
  for relative in payload.paths {
    guard relative.split("/").collect()
      is [".openseek", "attachments", id, name] &&
      attachment_name_is_safe(id.to_owned()) &&
      attachment_name_is_safe(name.to_owned()) &&
      is_document_attachment(name.to_owned()) else {
      raise InvalidRequest("only imported workspace attachments can be staged")
    }
    let target = root.join((relative : @pathx.Relative))
    if @fs.exists(target.to_string()) {
      let existing = load_attachment(AttachmentPath(target.resource_path()))
      guard existing.path is Some(existing_path) && root.contains(existing_path) else {
        raise InvalidRequest("attachment escapes the workspace")
      }
      continue
    }
    let source = source_root.join((relative : @pathx.Relative))
    let file = load_attachment(AttachmentPath(source.resource_path()))
    guard file.path is Some(source_path) && source_root.contains(source_path) else {
      raise InvalidRequest("attachment source escapes the workspace")
    }
    ignore(
      ensure_attachment_directory(
        root,
        target.to_path().dirname().relative(base=root.to_path()).to_string(),
      ),
    )
    @fs.write_binary(target.to_string(), file.bytes, create_mode=CreateNew) catch {
      @os_error.OsError(AlreadyExists, ..) => {
        let existing = load_attachment(AttachmentPath(target.resource_path()))
        guard existing.bytes == file.bytes else {
          raise InvalidRequest(
            "an attachment already exists with different contents",
          )
        }
      }
      error => raise error
    }
  }
  Acknowledged
}
