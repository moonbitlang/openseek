///|
#derive(Eq)
priv struct SessionSuggestionOwner {
  source : ConversationSelection
  connection_generation : Int32
}

///|
#derive(Eq)
priv struct SessionSuggestionEntry {
  owner : SessionSuggestionOwner
  sequence : Int32
  block : Int32
  state : @transcript_component.SessionSuggestionState
}

///|
#derive(Eq)
priv struct SessionSuggestionLookup {
  owner : SessionSuggestionOwner
  generation : Int32
}

///|
#derive(Eq)
priv struct SessionSuggestions {
  entries : Array[SessionSuggestionEntry]
  lookup : SessionSuggestionLookup?
  generation : Int32
}

///|
fn SessionSuggestions::empty() -> SessionSuggestions {
  { entries: [], lookup: None, generation: 0, }
}

///|
priv enum SessionSuggestionMsg {
  Start(slot~ : String, @transcript_component.SessionSuggestionRequest)
  Created(
    SessionSuggestionOwner,
    @transcript_component.SessionSuggestionRequest,
    Result[@protocol.SessionCreateFromMessageReply, String]
  )
  Loaded(
    SessionSuggestionLookup,
    Result[@protocol.SessionSuggestionsReply, String]
  )
}

///|
/// Only a saved, writable host conversation supplies session-creation actions.
/// The source identity is captured before any asynchronous work begins.
fn Model::session_suggestion_source(self : Model) -> SessionSuggestionOwner? {
  guard self.screen is Chat &&
    !self.cloud_selected() &&
    self.active_conversation() is Some(conv) &&
    conv.can_fork() &&
    self.conversation_selection() is Some(source) &&
    source.matches_record(
      conv.device,
      conv.session_id,
      conv.project(),
      conv.record,
    ) &&
    self.device_state(source.channel) is Some(device) &&
    device.bridge is Connected &&
    device.reconnect_failures == 0 else {
    return None
  }
  Some({ source, connection_generation: device.connection_generation, })
}

///|
fn Model::visible_session_suggestions(
  self : Model,
) -> Array[(Int32, Int32, @transcript_component.SessionSuggestionState)] {
  guard self.session_suggestion_source() is Some(owner) else { return [] }
  self.session_suggestions.entries
  .filter(entry => entry.owner.source == owner.source)
  .map(entry => (entry.sequence, entry.block, entry.state))
}

///|
fn Model::with_session_suggestion(
  self : Model,
  entry : SessionSuggestionEntry,
) -> Model {
  let entries = self.session_suggestions.entries.filter(previous => {
    previous.owner.source != entry.owner.source ||
    previous.sequence != entry.sequence ||
    previous.block != entry.block
  })
  entries.push(entry)
  { ..self, session_suggestions: { ..self.session_suggestions, entries, }, }
}

///|
fn suggestion_answer(item : @transcript.TranscriptItem) -> String? {
  match item.kind {
    Assistant(prose~, finished=true, replay=false, ..) => prose
    Answer(text) => Some(text)
    _ => None
  }
}

///|
fn update_session_suggestion(
  emit : @cmd.Emit[Msg],
  message : SessionSuggestionMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match message {
    Start(slot~, request) => {
      guard model.transcript_slot().map(current => current.key()) == Some(slot) &&
        model.session_suggestion_source() is Some(owner) &&
        model.active_conversation() is Some(conv) &&
        request.block >= 0 &&
        !request.prompt.is_blank() &&
        conv.messages.any(item => {
          item.sequence == Some(request.sequence) &&
          suggestion_answer(item) is Some(_)
        }) else {
        return (@cmd.none, model)
      }
      if model.session_suggestions.entries.any(entry => {
          entry.owner.source == owner.source &&
          entry.sequence == request.sequence &&
          entry.block == request.block &&
          entry.state is (Starting | Started(..))
        }) {
        return (@cmd.none, model)
      }
      let payload : @protocol.SessionCreateFromMessagePayload = {
        session: owner.source.session,
        workspace: owner.source.workspace.path,
        sequence: request.sequence,
        block: request.block,
        prompt: request.prompt,
        model: conv.engine_model.to_string(),
        thinking: model.conversation_reasoning(conv),
        approval: model.approval_for(conv.device, conv.session_id),
      }
      (
        create_suggested_session(emit, owner, request, payload),
        model.with_session_suggestion({
          owner,
          sequence: request.sequence,
          block: request.block,
          state: Starting,
        }),
      )
    }
    Created(owner, request, result) => {
      guard model.device_state(owner.source.channel) is Some(device) &&
        device.connection_generation == owner.connection_generation else {
        return (@cmd.none, model)
      }
      if result is Err(_) &&
        model.session_suggestions.entries.any(entry => {
          entry.owner.source == owner.source &&
          entry.sequence == request.sequence &&
          entry.block == request.block &&
          entry.state is Started(..)
        }) {
        return (@cmd.none, model)
      }
      let state : @transcript_component.SessionSuggestionState = match result {
        Ok(reply) => Started(session=reply.session, archived=reply.archived)
        Err(message) => Failed(message~)
      }
      let model = model.with_session_suggestion({
        owner,
        sequence: request.sequence,
        block: request.block,
        state,
      })
      let model = if result is Ok(_) &&
        model.session_suggestions.lookup.map_or(false, lookup => {
          lookup.owner.source == owner.source
        }) {
        {
          ..model,
          session_suggestions: { ..model.session_suggestions, lookup: None, },
        }
      } else {
        model
      }
      // The source stays on screen; normal session/worktree broadcasts populate
      // the sidebar. Opening the new conversation is a separate button action.
      (@cmd.none, model)
    }
    Loaded(lookup, result) => {
      guard model.session_suggestions.lookup == Some(lookup) &&
        model.device_state(lookup.owner.source.channel) is Some(device) &&
        device.connection_generation == lookup.owner.connection_generation else {
        return (@cmd.none, model)
      }
      match result {
        Ok(reply) => {
          let entries = model.session_suggestions.entries.filter(entry => {
            entry.owner.source != lookup.owner.source ||
            !(entry.state is Started(..))
          })
          let mut model = {
            ..model,
            session_suggestions: { ..model.session_suggestions, entries, },
          }
          for suggestion in reply.suggestions {
            model = model.with_session_suggestion({
              owner: lookup.owner,
              sequence: suggestion.sequence,
              block: suggestion.block,
              state: Started(
                session=suggestion.session,
                archived=suggestion.archived,
              ),
            })
          }
          (@cmd.none, model)
        }
        Err(message) => model.notify_error(emit, message)
      }
    }
  }
}

///|
/// A successful host reply is already a durable target, even before the sidebar
/// refresh arrives. Open it with the known workspace rather than looking up its
/// id in a possibly older sidebar snapshot.
fn Model::open_suggested_session(
  self : Model,
  emit : @cmd.Emit[Msg],
  slot : String,
  session : String,
) -> (@cmd.Cmd, Model)? {
  guard self.transcript_slot().map(current => current.key()) == Some(slot) &&
    self.session_suggestion_source() is Some(owner) else {
    return None
  }
  let entry = self.session_suggestions.entries
    .iter()
    .find_first(entry => {
      entry.owner.source == owner.source &&
      entry.state is Started(session=target, ..) &&
      target == session
    })
  guard entry is Some({ state: Started(archived~, ..), .. }) else {
    return None
  }
  let source = owner.source
  let record : ConversationRecord = if archived {
    ArchivedRecord
  } else {
    LiveRecord
  }
  let target : ConversationSelection = {
    channel: source.channel,
    session,
    workspace: source.workspace,
    record,
  }
  let conversation = self
    .find_conversation(source.channel, session)
    .filter(conv => {
      target.matches_record(
        conv.device,
        conv.session_id,
        conv.project(),
        conv.record,
      )
    })
    .unwrap_or_else(() => {
      self.stored_conversation(
        source.channel,
        session,
        source.workspace,
        record,
      )
    })
  let model = {
    ..self.replace_conversation(conversation),
    selected_conversation: Some(HostSelection(target)),
    conversation_load_failure: None,
    screen: Chat,
  }
  Some(
    if archived {
      model.open_archived_session_on(
        emit,
        source.channel,
        session,
        source.workspace,
      )
    } else {
      let (model, generation) = model.begin_transcript_reload(conversation)
      let model = {
        ..model,
        loading_conversation: Some({ channel: source.channel, session, }),
      }.with_active_project(Some(source.workspace))
      (
        generation.map_or(@cmd.none, generation => {
          session_snapshot_command(
            emit,
            source.channel,
            model,
            session,
            generation,
            true,
          )
        }),
        model,
      )
    },
  )
}

///|
/// Recover successful actions when an answer is opened or the host reconnects.
/// A source notification also updates other clients viewing the same answer.
fn reconcile_session_suggestions(
  emit : @cmd.Emit[Msg],
  message : Msg,
  previous : Model,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.session_suggestion_source() is Some(owner) &&
    model.active_conversation() is Some(conv) else {
    return (@cmd.none, model)
  }
  let refreshed = match message {
    FromDevice(channel, SessionsChanged(key~, ..)) =>
      channel == owner.source.channel &&
      key.workspace == owner.source.workspace &&
      (
        key.session == owner.source.session ||
        model.session_suggestions.entries.any(entry => {
          entry.owner.source == owner.source &&
          entry.state is Started(session~, ..) &&
          session == key.session
        })
      )
    _ => false
  }
  // Ordinary composer edits do not rescan the transcript. A first durable
  // answer can introduce this capability after its source was already opened.
  let transcript_changed = previous
    .find_conversation(owner.source.channel, owner.source.session)
    .map(old => old.watermark) !=
    Some(conv.watermark)
  let created = message is SessionSuggestion(Created(created_owner, _, Ok(_))) &&
    created_owner == owner
  let needs_load = previous.session_suggestion_source() != Some(owner) ||
    refreshed ||
    created ||
    (
      transcript_changed &&
      model.session_suggestions.lookup.map_or(true, lookup => {
        lookup.owner != owner
      })
    )
  guard needs_load else { return (@cmd.none, model) }
  guard conv.messages.any(item => {
    suggestion_answer(item).map_or(false, text => {
      text.contains("openseek-session create")
    })
  }) else {
    return (@cmd.none, model)
  }
  let lookup : SessionSuggestionLookup = {
    owner,
    generation: model.session_suggestions.generation + 1,
  }
  let entries = model.session_suggestions.entries.map(entry => {
    if entry.owner.source == owner.source &&
      entry.owner.connection_generation != owner.connection_generation &&
      entry.state is Starting {
      {
        ..entry,
        owner,
        state: Failed(
          message=match model.locale {
            SimplifiedChinese =>
              "连接已中断。请重试以查看启动结果。"
            TraditionalChinese =>
              "連線已中斷。請重試以查看啟動結果。"
            Japanese =>
              "接続が中断されました。再試行して起動結果を確認してください。"
            Spanish =>
              "Se interrumpió la conexión. Reintenta para comprobar el inicio."
            English =>
              "The connection was interrupted. Retry to check the start result."
          },
        ),
      }
    } else {
      entry
    }
  })
  (
    load_session_suggestions(emit, lookup),
    {
      ..model,
      session_suggestions: {
        entries,
        lookup: Some(lookup),
        generation: lookup.generation,
      },
    },
  )
}

///|
fn create_suggested_session(
  emit : @cmd.Emit[Msg],
  owner : SessionSuggestionOwner,
  request : @transcript_component.SessionSuggestionRequest,
  payload : @protocol.SessionCreateFromMessagePayload,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionCreateFromMessageReply, String] = Ok(
        @interop.bridge_request(
          owner.source.channel,
          @commands.session_create_from_message,
          payload,
        ),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(emit(SessionSuggestion(Created(owner, request, result))))
    })
    |> ignore
  })
}

///|
fn load_session_suggestions(
  emit : @cmd.Emit[Msg],
  lookup : SessionSuggestionLookup,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionSuggestionsReply, String] = Ok(
        @interop.bridge_request(
          lookup.owner.source.channel,
          @commands.session_suggestions,
          {
            session: lookup.owner.source.session,
            workspace: lookup.owner.source.workspace.path,
          },
        ),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(emit(SessionSuggestion(Loaded(lookup, result))))
    })
    |> ignore
  })
}
