///|
/// Owns only the client response stream. Closing it never cancels the Cloud
/// task: revisiting that session recovers through GET and polling.
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
priv suberror StreamSubscription {
  StreamSubscription(StreamLease)
}

///|
pub fn subscriptions(state : State) -> @sub.Sub {
  let streams : Array[@sub.Sub] = []
  for id, conversation in state.conversations {
    if conversation.stream is Some(stream) {
      streams.push(
        @sub.custom_sub(
          "cloud-stream-" +
          state.epoch.to_string() +
          ":" +
          id +
          ":" +
          conversation.request.to_string(),
          Local,
          StreamSubscription(stream),
          (payload, _) => {
            guard payload is StreamSubscription(stream) else { return None }
            Some({ unload: _ => stream.close(), update_tagger: _ => (), })
          },
        ),
      )
    }
  }
  @sub.batch(streams)
}
