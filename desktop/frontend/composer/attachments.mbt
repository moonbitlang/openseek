///|
priv enum AttachmentPhase {
  AttachmentPreparing
  AttachmentConfirming(name~ : String)
  AttachmentImporting
} derive(Eq)

///|
priv struct AttachmentRequest {
  id : Int32
  source : @protocol.AttachmentSource
  root : @common.Uri
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
  if input.identity.owner.channel != @interop.Local ||
    input.root is None ||
    @interop.openseek_api() is None {
    return @image_input.pick(
      locale~,
      allow_images=input.presentation.images_enabled,
      emit,
    )
  }
  @cmd.custom_cmd(scheduler => {
    scheduler.add(emit(@image_input.Reading))
    @js.Promise::from_async(() => {
      let reply : @protocol.PickAttachmentReply = @interop.bridge_request(
        input.identity.owner.channel,
        @commands.host_pick_attachment,
        @protocol.NoPayload,
      ) catch {
        error => {
          scheduler.add(
            emit(@image_input.Failed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(emit(@image_input.NativeReady(reply.path)))
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
      let reply : @protocol.PrepareAttachmentReply = @interop.bridge_request(
        identity.owner.channel,
        @commands.fs_prepare_attachment,
        {
          session: identity.owner.session,
          workspace: request.root.path,
          source: request.source,
        },
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
      let reply : @protocol.ImportAttachmentReply = @interop.bridge_request(
        identity.owner.channel,
        @commands.fs_import_attachment,
        {
          session: identity.owner.session,
          workspace: request.root.path,
          source: request.source,
        },
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
  guard self.root is Some(root) else {
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
      root,
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
  self.attachment_requests.map(request => {
    match request.phase {
      AttachmentConfirming(name~) =>
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
                  AttachmentConfirmed(self.identity(), request.root, request.id),
                ),
                ui(locale, UploadAttachment),
              ),
              @html.button(
                type_="button",
                class="composer-goal-action",
                on_click=emit(
                  AttachmentCancelled(self.identity(), request.root, request.id),
                ),
                ui(locale, CancelAttachment),
              ),
            ]),
          ],
        )
      AttachmentPreparing | AttachmentImporting =>
        @html.div(
          class="composer-context-row composer-image-notice",
          ui(locale, PreparingAttachment),
        )
    }
  })
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
