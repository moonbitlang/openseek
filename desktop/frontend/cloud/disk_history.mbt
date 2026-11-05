///|
fn History::cache_page(self : History) -> @protocol.CloudHistoryCachePage {
  {
    session: self.session,
    messages: self.messages.map(record => {
      "task_id": record.task_id,
      "kind": record.kind,
      "data": record.data,
      "created_at": record.created_at,
      "engine_sequence": record.engine_sequence.map_or(Json::null(), value => {
        Json(value)
      }),
    }),
    offset: self.offset,
    etag: self.etag,
  }
}

///|
fn cached_history(page : @protocol.CloudHistoryCachePage) -> History? {
  let fields : Map[String, Json] = {
    "session": page.session.to_json(),
    "messages": Json(page.messages),
    "generating": Json(false),
  }
  if page.offset is Some(offset) {
    fields["page"] = { "offset": offset }
  }
  let history = decode_history(Json(fields)) catch { _ => return None }
  Some({ ..history, etag: page.etag, })
}

///|
async fn history_cache(
  token : String,
  action : @protocol.CloudHistoryCacheAction,
) -> @protocol.CloudHistoryCacheReply {
  @interop.bridge_request(Local, @commands.cloud_history_cache, {
    token,
    action,
  }) catch {
    _ => Done
  }
}

///|
fn cache_mutation(
  enabled : Bool,
  token : String?,
  action : @protocol.CloudHistoryCacheAction,
) -> @cmd.Cmd {
  guard enabled && token is Some(token) else { return @cmd.none }
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => ignore(history_cache(token, action)))
    |> ignore
  })
}

///|
fn State::read_disk_history(
  self : State,
  session : String,
  token : String,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  let request = self.sequence + 1
  let conversation = self.conversations[session]
  (
    { ..self, sequence: request, }.replace(session, {
      ..conversation,
      request,
      history_reading: true,
      history_disk_request: Some(request),
    }),
    run(emit, () => {
      let history = match history_cache(token, Read(session~)) {
        Page(Some(page)) => cached_history(page)
        _ => None
      }
      DiskHistoryLoaded(self.epoch, session, request, history)
    }),
  )
}

///|
/// Cached rows are navigation fallbacks only. Their titles and archive status
/// have not been confirmed by the Cloud catalog.
pub fn State::sidebar_sessions(self : State) -> Array[Session] {
  if self.sessions.is_empty() {
    self.cached_sessions
  } else {
    self.sessions
  }
}

///|
/// Save the completed turn using its native boundaries. The service assigns
/// the page offset and ETag, so the next online open obtains those from GET.
fn Conversation::completed_cache_page(
  self : Conversation,
  outcome : Event,
) -> @protocol.CloudHistoryCachePage? {
  guard self.terminal_record is Some((task, end)) && task == outcome.task_id else {
    return None
  }
  let events = self.document.events.unwrap_or([])
  // Opening an already-running turn can obtain its User anchor from history.
  let user_start = self.records
    .iter()
    .find_first(record => {
      record.task_id == task &&
      record.kind == "user" &&
      record.engine_sequence is Some(_)
    })
    .bind(record => record.engine_sequence)
  guard (match (self.turn_start_sequence, user_start) {
      (Some(start), Some(user)) => Some(start.min(user))
      (Some(start), None) | (None, Some(start)) => Some(start)
      (None, None) => None
    })
    is Some(start) else {
    return None
  }
  let turn = events.filter(event => {
    event.sequence >= start && event.sequence <= end
  })
  guard !turn.is_empty() && turn.length() == end - start + 1 else {
    return None
  }
  let messages : Array[Json] = []
  for event in turn {
    if event.item is @protocol.User(user) {
      messages.push({
        "task_id": task,
        "kind": "user",
        "data": user.to_json(),
        "created_at": event.ts.unwrap_or(0.0),
        "engine_sequence": event.sequence,
      })
    }
  }
  guard !messages.is_empty() else { return None }
  messages.push({
    "task_id": task,
    "kind": "task_finished",
    "data": outcome.data,
    "created_at": turn.last().bind(event => event.ts).unwrap_or(0.0),
  })
  Some({
    session: { ..self.document, events: Some(turn), },
    messages,
    offset: None,
    etag: None,
  })
}
