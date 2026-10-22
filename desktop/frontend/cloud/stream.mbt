///|
/// Owns only the client response stream. Closing it never cancels the Cloud
/// task: revisiting that session recovers history and a fresh control snapshot.
pub struct StreamLease {
  mut active : Bool
  mut client : @http.Client?
}

///|
fn StreamLease::new() -> StreamLease {
  { active: true, client: None, }
}

///|
impl Eq for StreamLease with fn equal(a, b) {
  physical_equal(a, b)
}

///|
fn StreamLease::close(self : StreamLease) -> Unit {
  self.active = false
  if self.client is Some(client) {
    client.close()
  }
  self.client = None
}

///|
priv suberror Observation {
  Observation
}

///|
pub fn subscriptions(
  state : State,
  selected : String?,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  guard selected is Some(id) &&
    token is Some(token) &&
    !state.is_archived(id) &&
    state.conversations.get(id) is Some(conversation) &&
    !conversation.loading else {
    return @sub.batch([])
  }
  @sub.custom_sub(
    "cloud-events-" +
    state.epoch.to_string() +
    ":" +
    id +
    ":" +
    conversation.watch_request.to_string(),
    Local,
    Observation,
    (_, scheduler) => {
      let stream = StreamLease::new()
      scheduler.add(emit(WatchOpened(state.epoch, id, stream)))
      @js.Promise::from_async(() => {
        let failure = try {
          watch_control(token, id, stream, event => {
            scheduler.add(emit(WatchEvent(state.epoch, id, stream, event)))
          })
          None
        } catch {
          @cloud_client.RequestError(error) => Some(error)
          _ => Some(Unreachable)
        }
        if stream.active {
          scheduler.add(emit(WatchEnded(state.epoch, id, stream, failure)))
        }
      })
      |> ignore
      Some({ unload: _ => stream.close(), update_tagger: _ => (), })
    },
  )
}
