///|
/// The host-op state, for the pumps spawned beside the dispatcher.
///
/// Exported on purpose: its only consumer is the desktop app, a module outside
/// this workspace that the API analyzer cannot see —
/// `desktop/app/internal/extension/session_export.mbt:42`.
pub fn ApiState::host_state(self : ApiState) -> @host.HostState {
  self.host
}

///|
/// The request-side engine coordination handle.
///
/// Exported on purpose: its only consumers are the desktop app, a module outside
/// this workspace that the API analyzer cannot see —
/// `desktop/app/internal/extension/extension.mbt:663` and
/// `desktop/app/internal/extension/session_export.mbt:45`.
pub fn ApiState::manager(self : ApiState) -> @engine.EngineManager {
  self.manager
}

///|
/// A replacement desktop page cannot return replies through the old page's
/// WebSockets. Keep its questions open and deliver subsequent answers as input.
///
/// Exported on purpose: its only consumer is the desktop app, a module outside
/// this workspace that the API analyzer cannot see —
/// `desktop/app/internal/extension/extension.mbt:526`.
pub fn ApiState::detach_cloud_questions(self : ApiState) -> Unit {
  for _, client in self.cloud_clients {
    for request in client.questions.snapshot().requests {
      client.questions.detach(request.session)
    }
  }
}
