///|
priv enum AttachmentPhase {
  AttachmentPreparing
  AttachmentConfirming(name~ : String)
  AttachmentImporting
  AttachmentStaged(name~ : String)
} derive(Eq)

///|
priv struct AttachmentRequest {
  id : Int32
  source : @protocol.AttachmentSource
  root : @common.Uri?
  cloud_access : @cloud_client.Access?
  phase : AttachmentPhase
} derive(Eq)

///|
fn pick_attachments(
  locale : @i18n.Locale,
  input : Input,
  emit : @cmd.Emit[@image_input.Event],
) -> @cmd.Cmd {
  // Native selection exposes an exact path. The browser File API deliberately
  // hides it, so browser/remote selections must upload their actual bytes.
  let host = match input.identity.owner.host() {
    Some(host) if host.channel == @interop.Local &&
      input.root is Some(_) &&
      @interop.openseek_api() is Some(_) => host
    _ =>
      return @image_input.pick(
        locale~,
        allow_images=input.presentation.images_enabled,
        emit,
      )
  }
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply : @protocol.PickAttachmentReply = @interop.bridge_request(
        host.channel,
        @commands.host_pick_attachment,
        @protocol.NoPayload,
      ) catch {
        error => {
          scheduler.add(
            emit(
              @image_input.NativePicked(Err(@interop.bridge_error_text(error))),
            ),
          )
          return
        }
      }
      scheduler.add(emit(@image_input.NativePicked(Ok(reply.path))))
    })
    |> ignore
  })
}

///|
fn prepare_attachment(
  identity : Identity,
  request : AttachmentRequest,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      if identity.owner is @interop.Cloud(session~, ..) &&
        request.cloud_access is Some(access) {
        let result = Ok(
          @cloud_client.prepare_attachment(
            access.token,
            session,
            request.source,
          ),
        ) catch {
          @cloud_client.RequestError(failure) => Err(failure.label())
          _ => Err(@cloud_client.Failure::Unreachable.label())
        }
        scheduler.add(
          emit(AttachmentPrepared(identity, request.root, request.id, result)),
        )
        return
      }
      guard identity.owner.host() is Some(host) && request.root is Some(root) else {
        return
      }
      let reply : @protocol.PrepareAttachmentReply = @interop.bridge_request(
        host.channel,
        @commands.fs_prepare_attachment,
        { session: host.session, workspace: root.path, source: request.source, },
      ) catch {
        error => {
          scheduler.add(
            emit(
              AttachmentPrepared(
                identity,
                request.root,
                request.id,
                Err(@interop.bridge_error_text(error)),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        emit(AttachmentPrepared(identity, request.root, request.id, Ok(reply))),
      )
    })
    |> ignore
  })
}

///|
fn import_attachment(
  identity : Identity,
  request : AttachmentRequest,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      if identity.owner is @interop.Cloud(session~, ..) &&
        request.cloud_access is Some(access) {
        let result = Ok(
          @cloud_client.import_attachment(access.token, session, request.source).path,
        ) catch {
          @cloud_client.RequestError(failure) => Err(failure.label())
          _ => Err(@cloud_client.Failure::Unreachable.label())
        }
        scheduler.add(
          emit(AttachmentImported(identity, request.root, request.id, result)),
        )
        return
      }
      guard identity.owner.host() is Some(host) && request.root is Some(root) else {
        return
      }
      let reply : @protocol.ImportAttachmentReply = @interop.bridge_request(
        host.channel,
        @commands.fs_import_attachment,
        { session: host.session, workspace: root.path, source: request.source, },
      ) catch {
        error => {
          scheduler.add(
            emit(
              AttachmentImported(
                identity,
                request.root,
                request.id,
                Err(@interop.bridge_error_text(error)),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        emit(
          AttachmentImported(identity, request.root, request.id, Ok(reply.path)),
        ),
      )
    })
    |> ignore
  })
}

///|
fn Entry::prepare_attachments(
  self : Entry,
  sources : Array[@protocol.AttachmentSource],
  emit : @cmd.Emit[Msg],
) -> (Entry, @cmd.Cmd) {
  if sources.is_empty() {
    return (self, @cmd.none)
  }
  guard self.root is Some(_) || self.owner is @interop.Cloud(..) else {
    return (
      {
        ..self,
        image_error: Some("Choose a workspace before attaching documents"),
      },
      @cmd.none,
    )
  }
  let requests = self.attachment_requests.copy()
  let commands : Array[@cmd.Cmd] = []
  let mut sequence = self.attachment_sequence
  for source in sources {
    sequence += 1
    let request = AttachmentRequest::{
      id: sequence,
      source,
      root: self.root,
      cloud_access: self.cloud_access,
      // Browser and remote files have no host-local path to resolve. Keep
      // their bytes in this draft until the user confirms the upload.
      phase: match source {
        AttachmentBytes(name~, ..) => AttachmentConfirming(name~)
        AttachmentPath(_) => AttachmentPreparing
      },
    }
    requests.push(request)
    if request.phase is AttachmentPreparing {
      commands.push(prepare_attachment(self.identity(), request, emit))
    }
  }
  (
    { ..self, attachment_requests: requests, attachment_sequence: sequence, },
    @cmd.batch(commands),
  )
}

///|
fn Entry::without_attachment(self : Entry, id : Int32) -> Entry {
  {
    ..self,
    attachment_requests: self.attachment_requests.filter(request => {
      request.id != id
    }),
  }
}

///|
fn Entry::attachment_failed(
  self : Entry,
  id : Int32,
  message : String,
) -> Entry {
  let next = if self.owner is @interop.Cloud(..) &&
    self.attachment_requests.iter().find_first(request => request.id == id)
    is Some(request) {
    self.with_attachment_phase(
      id,
      AttachmentConfirming(name=attachment_name(request.source)),
    )
  } else {
    self.without_attachment(id)
  }
  { ..next, image_error: Some(message), }
}

///|
fn Entry::with_attachment_phase(
  self : Entry,
  id : Int32,
  phase : AttachmentPhase,
) -> Entry {
  {
    ..self,
    attachment_requests: self.attachment_requests.map(request => {
      if request.id == id {
        { ..request, phase, }
      } else {
        request
      }
    }),
  }
}

///|
fn Entry::attachment_reference(self : Entry, path : String) -> Entry {
  {
    ..self,
    draft: self.draft.with_mention({
      ref_: @mention_context.File(path~),
      range: None,
    }),
  }
}

///|
fn Entry::attachment_confirmations(
  self : Entry,
  locale : @i18n.Locale,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  self.attachment_requests.filter_map(request => {
    match request.phase {
      AttachmentStaged(_) => None
      AttachmentConfirming(name~) =>
        Some(
          @html.div(
            class="composer-context-row composer-attachment-confirm",
            attrs=@html.Attrs::build()
              .role("group")
              .aria_label(ui(locale, UploadAttachment)),
            [
              @html.div(class="composer-attachment-name", name),
              @html.div(
                class="composer-attachment-question",
                ui(locale, UploadAttachmentQuestion),
              ),
              @html.div(class="composer-attachment-actions", [
                @html.button(
                  type_="button",
                  class="composer-goal-action",
                  on_click=emit(
                    AttachmentConfirmed(
                      self.identity(),
                      request.root,
                      request.id,
                    ),
                  ),
                  ui(locale, UploadAttachment),
                ),
                @html.button(
                  type_="button",
                  class="composer-goal-action",
                  on_click=emit(
                    AttachmentCancelled(
                      self.identity(),
                      request.root,
                      request.id,
                    ),
                  ),
                  ui(locale, CancelAttachment),
                ),
              ]),
            ],
          ),
        )
      AttachmentPreparing | AttachmentImporting =>
        Some(
          @html.div(
            class="composer-context-row composer-image-notice",
            ui(locale, PreparingAttachment),
          ),
        )
    }
  })
}

///|
fn attachment_name(source : @protocol.AttachmentSource) -> String {
  match source {
    AttachmentBytes(name~, ..) => name
    AttachmentPath(path) => path
  }
}

///|
/// Reuse file mentions while ensuring an uploaded original is present in a
/// task's newly created worktree. No extraction or sidecar file is involved.
pub async fn stage_attachments(
  channel : @interop.ChannelId,
  session : String,
  workspace : String,
  source_root : String,
  mentions : Array[@mention_context.MentionRef],
) -> Unit {
  let paths : Array[String] = []
  for mention in mentions {
    if mention is @mention_context.File(path~) &&
      path.has_prefix(".openseek/attachments/") &&
      !paths.contains(path) {
      paths.push(path)
    }
  }
  if paths.is_empty() {
    return
  }
  ignore(
    @interop.bridge_request(channel, @commands.fs_stage_attachments, {
      session,
      workspace,
      source_root,
      paths,
    }),
  )
}
