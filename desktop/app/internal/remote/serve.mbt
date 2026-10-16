///|
/// Relay registration/dialling stays native; request scheduling and delivery
/// run through the same shared transport as a headless host connection.
priv struct WsClientActor {
  state : @api.DesktopState
}

///|
fn WsClientActor::WsClientActor(state : @api.DesktopState) -> WsClientActor {
  { state, }
}

///|
async fn WsClientActor::run(self : WsClientActor, url : String) -> Unit {
  let conn = @websocket.Conn::connect(url)
  defer conn.close()
  self.serve(conn) catch {
    _ => ()
  }
}

///|
async fn WsClientActor::serve(
  self : WsClientActor,
  conn : @websocket.Conn,
) -> Unit {
  let connection = self.state.new_connection()
  let handlers : Array[@transport.RequestHandler] = @api.endpoints(
    self.state,
    connection,
  ).map(endpoint => {
    name: endpoint.name(),
    invoke: params => endpoint.invoke(params),
  })
  let client = @transport.Client(
    handlers,
    (emit, on_lag) => {
      let sub = self.state.subscribe_with(
        offer=event => emit(event.transport_notification()),
        on_lag=sub => {
          sub.close()
          on_lag()
        },
      )
      () => sub.close()
    },
    (emit, progress) => {
      connection.run(event => emit(event.transport_notification()), event => {
        progress(event.transport_notification())
      })
    },
  )
  client.serve(conn, make_endpoints=notify => {
    @api.endpoints(self.state, connection, on_share_progress=payload => {
      notify(
        @protocol.Notification::SessionShareProgress(payload).transport_notification(),
      )
    }).map(endpoint => {
      name: endpoint.name(),
      invoke: params => endpoint.invoke(params),
    })
  })
}

///|
fn @protocol.Notification::transport_notification(
  self : @protocol.Notification,
) -> @transport.Notification {
  match self {
    UserQuestions(payload) =>
      @transport.Notification::from_host(UserQuestions(payload))
    AgentApprovals(payload) =>
      @transport.Notification::from_host(AgentApprovals(payload))
    AgentConnected(payload) =>
      @transport.Notification::from_host(AgentConnected(payload))
    AgentStarted(payload) =>
      @transport.Notification::from_host(AgentStarted(payload))
    AgentEvent(payload) =>
      @transport.Notification::from_host(AgentEvent(payload))
    AgentError(payload) =>
      @transport.Notification::from_host(AgentError(payload))
    AgentPrediction(payload) =>
      @transport.Notification::from_host(AgentPrediction(payload))
    AgentFinished(payload) =>
      @transport.Notification::from_host(AgentFinished(payload))
    SessionEvent(payload) =>
      @transport.Notification::from_host(SessionEvent(payload))
    SubrunProgress(payload) =>
      @transport.Notification::from_host(SubrunProgress(payload))
    WorkflowEntry(payload) =>
      @transport.Notification::from_host(WorkflowEntry(payload))
    SessionChanged(payload) =>
      @transport.Notification::from_host(SessionChanged(payload))
    WorkspaceChanged(payload) =>
      @transport.Notification::from_host(WorkspaceChanged(payload))
    WorkspaceSettingsChanged(payload) =>
      @transport.Notification::from_host(WorkspaceSettingsChanged(payload))
    WorktreeChanged(payload) =>
      @transport.Notification::from_host(WorktreeChanged(payload))
    SettingsChanged(payload) =>
      @transport.Notification::from_host(SettingsChanged(payload))
    SkillsChanged => @transport.Notification::from_host(SkillsChanged)
    CodexStatusChanged(payload) =>
      @transport.Notification::from_host(CodexStatusChanged(payload))
    CodexNotification(payload) =>
      @transport.Notification::from_host(CodexNotification(payload))
    CodexServerRequest(payload) =>
      @transport.Notification::from_host(CodexServerRequest(payload))
    LspDiagnostics(payload) =>
      @transport.Notification::from_host(LspDiagnostics(payload))
    FsChanged(payload) => @transport.Notification::from_host(FsChanged(payload))
    FsWatchFailed(payload) =>
      @transport.Notification::from_host(FsWatchFailed(payload))
    TerminalOutput(payload) =>
      @transport.Notification::from_host(TerminalOutput(payload))
    TerminalExit(payload) =>
      @transport.Notification::from_host(TerminalExit(payload))
    SemanticSearchProgress(payload) =>
      @transport.Notification::from_host(SemanticSearchProgress(payload))
    SessionShareProgress(_)
    | AuthChanged(_)
    | UpdateDownloadProgress(_)
    | UpdateDownloaded(_)
    | UpdateDownloadFailed(_) =>
      @transport.Notification::other(self.wire_name(), self.params())
  }
}
