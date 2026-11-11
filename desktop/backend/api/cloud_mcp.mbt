///|
/// These are client-side questions only, never Local engine sessions or history.
priv struct CloudMcpClient {
  token : String
  questions : @user_questions.Service
  dispatcher : @mcp.Dispatcher
}

///|
fn ApiState::cloud_mcp_client(
  self : ApiState,
  account : String,
) -> CloudMcpClient raise {
  guard self.auth.account() is Some(credentials) &&
    credentials.user.user_id == account else {
    raise @host.HostError("Cloud MCP account is no longer signed in")
  }
  // A changed account retires all old question state. In-flight callbacks also
  // check the client identity before publishing or delivering anything.
  for old in self.cloud_clients.keys().to_array() {
    if old != account {
      self.cloud_clients.remove(old)
    }
  }
  if self.cloud_clients.get(account) is Some(client) &&
    client.token == credentials.token {
    return client
  }
  guard self.cloud_browser is Some(browser) else {
    raise @host.HostError("Cloud client tools require the desktop window")
  }
  let questions = @user_questions.Service()
  let client : CloudMcpClient = {
    token: credentials.token,
    questions,
    dispatcher: Dispatcher(
      [
        browser(account),
        self.preview_tool(account~),
        ask_user_tool(questions, _ => (), () => {
          self.cloud_questions_changed(account, questions)
        }),
      ],
      version=self.app_version,
    ),
  }
  self.cloud_clients[account] = client
  client
}

///|
fn ApiState::cloud_questions_changed(
  self : ApiState,
  account : String,
  questions : @user_questions.Service,
) -> Unit {
  guard self.auth.account() is Some(credentials) &&
    credentials.user.user_id == account &&
    self.cloud_clients
    .get(account)
    .map_or(false, client => {
      client.token == credentials.token &&
      physical_equal(client.questions, questions)
    }) else {
    return
  }
  self.publish(CloudMcp(Questions(account~, snapshot=questions.snapshot())))
  // TODO: acknowledge delayed input delivery across frontend disconnects.
  for (session, text, id) in questions.take_inputs() {
    self.publish(CloudMcp(Input(account~, session~, text~, id~)))
  }
}

///|
async fn ApiState::cloud_mcp(
  self : ApiState,
  request : @protocol.CloudMcpRequest,
) -> Json {
  let account = request.account()
  let client = self.cloud_mcp_client(account)
  match request {
    Dispatch(session~, message~, ..) =>
      client.dispatcher.dispatch(message, session~).unwrap_or(null)
    Detach(session~, ..) => {
      client.questions.detach(session)
      null
    }
    Questions(..) => client.questions.snapshot().to_json()
    Answer(answer~, ..) => {
      client.questions.answer(answer)
      self.cloud_questions_changed(account, client.questions)
      client.questions.snapshot().to_json()
    }
  }
}

///|
/// A replacement desktop page cannot return replies through the old page's
/// WebSockets. Keep its questions open and deliver subsequent answers as input.
pub fn ApiState::detach_cloud_questions(self : ApiState) -> Unit {
  for _, client in self.cloud_clients {
    for request in client.questions.snapshot().requests {
      client.questions.detach(request.session)
    }
  }
}
