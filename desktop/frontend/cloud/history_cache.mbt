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
fn native_history_cache() -> Bool {
  @interop.openseek_api().map_or(false, api => {
    @interop.js_prop(api, @commands.cloud_history_cache.name()) is Some(_)
  })
}

///|
async fn State::history_cache(
  self : State,
  token : String,
  action : @protocol.CloudHistoryCacheAction,
) -> @protocol.CloudHistoryCacheReply {
  if native_history_cache() {
    @interop.bridge_request(Local, @commands.cloud_history_cache, {
      token,
      action,
    }) catch {
      _ => Done
    }
  } else {
    self.indexed_history_cache(action)
  }
}

///|
fn State::cache_mutation(
  self : State,
  token : String?,
  action : @protocol.CloudHistoryCacheAction,
) -> @cmd.Cmd {
  guard token is Some(token) else { return @cmd.none }
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => ignore(self.history_cache(token, action)))
    |> ignore
  })
}

///|
fn State::read_persistent_history(
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
      history_cache_request: Some(request),
    }),
    run(emit, () => {
      let history = match self.history_cache(token, Read(session~)) {
        Page(Some(page)) => cached_history(page)
        _ => None
      }
      CachedHistoryLoaded(self.epoch, session, request, history)
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
