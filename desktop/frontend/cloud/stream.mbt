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
fn retry_observation(failure : Failure?) -> Bool {
  match failure {
    None | Some(Unreachable) => true
    Some(Http(status)) =>
      status == 408 || status == 429 || (status >= 500 && status < 600)
    _ => false
  }
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
    !state.needs_sign_in &&
    !state.is_archived(id) &&
    !state.retired.contains(id) &&
    !state.deletions.contains(id) &&
    !(state.metadata_saves.get(id) is Some({ edit: Archive(true), .. })) &&
    state.conversations.get(id) is Some(conversation) &&
    conversation.watch_status != Disconnected &&
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
      let start = () => {
        guard stream.active else { return }
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
      }
      // The subscription owns the timer as well as the stream. Leaving the
      // conversation cancels both; a delayed callback cannot reopen it.
      let timer = if conversation.watch_status == Reconnecting {
        Some(@base_browser.schedule_timeout(start, 1500))
      } else {
        start()
        None
      }
      Some({
        unload: _ => {
          if timer is Some(timer) {
            timer.dispose()
          }
          stream.close()
        },
        update_tagger: _ => (),
      })
    },
  )
}
