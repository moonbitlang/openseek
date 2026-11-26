///|
const CloudSubagentsDialog = "cloud-subagent-transcripts"

///|
#derive(Eq)
priv enum CloudSubagentContent {
  Children(Array[String])
  History(Array[@transcript.TranscriptItem])
}

///|
#derive(Eq)
priv struct CloudSubagents {
  owner : @interop.ConversationIdentity
  epoch : Int32
  child : String?
  content : Result[CloudSubagentContent, @cloud_client.Failure]?
  preview : Int32?
}

///|
async fn read_cloud_subagents(
  token : String,
  session : String,
  child : String?,
) -> CloudSubagentContent {
  let path = "/v1/sessions/\{@uri.encode_component(session)}/subagents"
  match child {
    None => {
      let body = @cloud_client.request(
        @cloud_client.CloudOrigin,
        path,
        Get,
        token~,
      )
      guard body is { "subagents": ids, .. } else {
        raise @cloud_client.RequestError(Malformed)
      }
      Children(@json.from_json(ids))
    }
    Some(id) => {
      let body = @cloud_client.request(
        @cloud_client.CloudOrigin,
        path + "/" + @uri.encode_component(id),
        Get,
        token~,
      )
      guard body is { "records": Array([header, .. events]), .. } &&
        header is { "id": String(record_id), .. } &&
        record_id == id else {
        raise @cloud_client.RequestError(Malformed)
      }
      let items = []
      for record in events {
        let event : @protocol.SessionEvent = @json.from_json(record)
        ignore(
          @transcript.apply_session_item(
            items,
            event.item,
            ts?=event.ts,
            sequence=event.sequence,
          ),
        )
      }
      History(items)
    }
  }
}

///|
fn open_cloud_subagents(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  child : String?,
) -> (@cmd.Cmd, Model) {
  guard model.cloud_identity() is Some(Cloud(account~, session~) as owner) &&
    model.account is Some(credentials) &&
    credentials.user.user_id == account &&
    model.cloud.user_id == Some(account) else {
    return (@cmd.none, model)
  }
  if child is Some(id) && @transcript.subrun_parent(id) != Some(session) {
    return (@cmd.none, model)
  }
  let generation = model.cloud_subagents_generation + 1
  let read = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[CloudSubagentContent, @cloud_client.Failure] = Ok(
        read_cloud_subagents(credentials.token, session, child),
      ) catch {
        @cloud_client.RequestError(failure) => Err(failure)
        _ => Err(@cloud_client.Malformed)
      }
      scheduler.add(dispatch(CloudSubagentsLoaded(generation, result)))
    })
    |> ignore
  })
  (
    @cmd.batch([
      if model.cloud_subagents is None {
        @dialog.show(CloudSubagentsDialog)
      } else {
        @cmd.none
      },
      read,
    ]),
    {
      ..model,
      cloud_subagents_generation: generation,
      cloud_subagents: Some({
        owner,
        epoch: model.cloud.epoch,
        child,
        content: None,
        preview: None,
      }),
    },
  )
}

///|
fn cloud_subagents_dialog(
  dispatch : @cmd.Emit[Msg],
  locale : @i18n.Locale,
  page : CloudSubagents?,
) -> @html.Html {
  let title = shell_text(locale, SubagentTranscripts)
  let children : Array[@html.Html] = []
  if page is Some(page) {
    let heading = page.child
      .bind(@transcript.subrun_label)
      .map_or(title, label => title + " · " + label)
    children.push(
      @rui.dialog_header(@rui.dialog_title(id="cloud-subagents-title", heading)),
    )
    let body : Array[@html.Html] = []
    if page.child is Some(_) {
      body.push(
        @html.button(
          class="button secondary",
          on_click=dispatch(OpenCloudSubagents(None)),
          title,
        ),
      )
    }
    match page.content {
      None => body.push(@html.p(shell_text(locale, LoadingConversation)))
      Some(Err(error)) => {
        body.push(@html.p(error.text(locale)))
        body.push(
          @html.button(
            class="button secondary",
            on_click=dispatch(OpenCloudSubagents(page.child)),
            shell_text(locale, RetryLabel),
          ),
        )
      }
      Some(Ok(Children(ids))) =>
        if ids.is_empty() {
          body.push(@html.p(shell_text(locale, NoSavedSubagents)))
        } else {
          for id in ids {
            body.push(
              @html.button(
                class="menu-option",
                on_click=dispatch(OpenCloudSubagents(Some(id))),
                @transcript.subrun_label(id).unwrap_or(id),
              ),
            )
          }
        }
      Some(Ok(History(items))) =>
        if items.is_empty() {
          body.push(@html.p(shell_text(locale, EmptySubagentTranscript)))
        } else {
          body.push(
            @transcript_component.saved_items_view(
              locale,
              items,
              path => dispatch(CloudSubagentLink(path)),
              preview=page.preview,
              toggle=index => dispatch(CloudSubagentMarkdown(index)),
            ),
          )
        }
    }
    children.push(@html.div(class="dialog-scroll-body dialog-content", body))
  }
  @rui.dialog(
    id=CloudSubagentsDialog,
    class="dialog-size-large dialog-surface dialog-scroll-layout",
    close_label=shell_text(locale, DismissLabel),
    on_close=_ => dispatch(CloseCloudSubagents),
    on_cancel=dispatch(CloseCloudSubagents),
    attrs=@html.Attrs::build().aria_labelledby("cloud-subagents-title"),
    children,
  )
}
