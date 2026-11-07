///|
/// Each opening captures its source and advances a generation. Late replies
/// from a dismissed dialog cannot overwrite a later conversation's dialog.
#derive(Eq, Debug)
struct Model {
  id_prefix : String
  generation : Int32
  visible : Bool
  content : Content?
}

///|
#derive(Eq, Debug)
priv enum Source {
  Host(@interop.ChannelId, @protocol.SessionExportPayload)
  Cloud(session~ : String)
  File(FileSource)
}

///|
#derive(Eq, Debug)
pub(all) enum FileSource {
  HostFile(@interop.ChannelId, @protocol.ReadFilePayload)
  CloudFile(account~ : String, session~ : String, path~ : String)
}

///|
#derive(Eq, Debug)
priv struct Content {
  source : Source
  operation : Operation
  // A completed link survives subsequent downloads and their errors.
  publication : Publication?
}

///|
#derive(Eq, Debug)
priv enum Operation {
  Ready
  Downloading
  Sharing(@protocol.ShareProgress)
  SigningIn
  SignInRequired
  SignInFailed(String)
  Saved(path~ : String, opened~ : Bool)
  Failed(String)
}

///|
#derive(Eq, Debug)
priv struct Publication {
  url : String
  copy : CopyState
}

///|
#derive(Eq, Debug)
priv enum CopyState {
  Available
  Copied
  Failed(String)
}

///|
pub(all) enum Msg {
  Close
  Download
  Share
  SignIn
  Downloaded(generation~ : Int32, Result[@protocol.SessionExportReply, String])
  Progress(@protocol.SessionShareProgress)
  HostProgress(@interop.ChannelId, @protocol.SessionShareProgress)
  Published(generation~ : Int32, @protocol.SessionShareReply)
  SignedIn(generation~ : Int32, Result[Unit, String])
  ClipboardFinished(generation~ : Int32, Result[Unit, String])
}

///|
/// The opening a reply belongs to; user actions always target the current one.
fn Msg::generation(self : Msg) -> Int32? {
  match self {
    Downloaded(generation~, _)
    | Published(generation~, _)
    | SignedIn(generation~, _)
    | ClipboardFinished(generation~, _) => Some(generation)
    Progress(payload) | HostProgress(_, payload) => Some(payload.generation)
    Close | Download | Share | SignIn => None
  }
}

///|
pub fn Model::Model(id_prefix~ : String = "conversation-export") -> Model {
  { id_prefix, generation: 0, visible: false, content: None, }
}

///|
pub fn Model::open(
  self : Model,
  source : @protocol.SessionExportPayload,
  channel~ : @interop.ChannelId = Local,
) -> (@cmd.Cmd, Model) {
  (
    @dialog.show(self.id_prefix + "-dialog"),
    {
      ..self,
      generation: self.generation + 1,
      visible: true,
      content: Some({
        source: Host(channel, source),
        operation: Ready,
        publication: None,
      }),
    },
  )
}

///|
fn Operation::busy(self : Operation) -> Bool {
  self is (Downloading | Sharing(_) | SigningIn)
}

///|
fn Model::showing(self : Model, content : Content) -> Model {
  { ..self, content: Some(content), }
}

///|
priv enum Effect {
  CloseDialog(cancel_sign_in~ : Bool)
  DownloadSource(Source)
  ShareSource(Source, @protocol.AccountSession)
  StartSignIn
}

///|
pub fn Model::update(
  self : Model,
  emit : @cmd.Emit[Msg],
  msg : Msg,
  account? : @protocol.AccountSession,
  desktop~ : Bool = true,
  sign_in~ : @cmd.Cmd = @cmd.none,
) -> (@cmd.Cmd, Model) {
  let (effect, next) = self.transition(msg, account?, desktop~)
  let command = match effect {
    None => @cmd.none
    Some(CloseDialog(cancel_sign_in=cancel)) => {
      let close = @dialog.close(self.id_prefix + "-dialog")
      if cancel {
        @cmd.batch([close, cancel_sign_in()])
      } else {
        close
      }
    }
    Some(DownloadSource(source)) =>
      next.download(emit, source, account, desktop~)
    Some(ShareSource(source, account)) =>
      next.share(emit, source, account, desktop~)
    Some(StartSignIn) => sign_in
  }
  (command, next)
}

///|
fn Model::transition(
  self : Model,
  msg : Msg,
  account? : @protocol.AccountSession,
  desktop~ : Bool = true,
) -> (Effect?, Model) {
  guard self.content is Some(content) else { return (None, self) }
  if msg.generation() is Some(generation) && generation != self.generation {
    return (None, self)
  }
  let msg = match msg {
    HostProgress(channel, payload) =>
      match content.source {
        Host(owner, _) if owner == channel => Progress(payload)
        _ => return (None, self)
      }
    _ => msg
  }
  let busy = content.operation.busy()
  match msg {
    Close =>
      // A browser sign-in this dialog started must not outlive it: the host
      // refuses a second auth.connect while one is still waiting.
      (
        Some(
          CloseDialog(cancel_sign_in=desktop && content.operation is SigningIn),
        ),
        {
          ..self,
          visible: false,
          content: if self.file_pending() {
            self.content
          } else {
            None
          },
        },
      )
    Download if !busy && !(content.source is File(_)) =>
      (
        Some(DownloadSource(content.source)),
        self.showing({ ..content, operation: Downloading, }),
      )
    Share if !busy && content.publication is None =>
      if content.source
        is (Host(Remote("host"), _) | File(HostFile(Remote("host"), _))) {
        (
          None,
          self.showing({
            ..content,
            operation: Failed(
              if content.source is File(_) {
                "Sharing is unavailable in the local debug console. Use SeekMoonDev.app or the hosted browser console."
              } else {
                "Sharing is unavailable in the local debug console. Use SeekMoonDev.app or the hosted browser console. You can still download this conversation."
              },
            ),
          }),
        )
      } else {
        match account {
          Some(account) => {
            let next = { ..self, generation: self.generation + 1, }
            (
              Some(ShareSource(content.source, account)),
              next.showing({ ..content, operation: Sharing(Preparing), }),
            )
          }
          None =>
            (None, self.showing({ ..content, operation: SignInRequired, }))
        }
      }
    SignIn if content.operation is (SignInRequired | SignInFailed(_)) =>
      (Some(StartSignIn), self.showing({ ..content, operation: SigningIn, }))
    Downloaded(result, ..) if content.operation is Downloading => {
      let operation = match result {
        Ok({ path: Some(path), opened, }) => Saved(path~, opened~)
        Ok({ path: None, .. }) => Ready
        Err(message) => Failed(message)
      }
      (None, self.showing({ ..content, operation, }))
    }
    Progress(payload) if content.operation is Sharing(_) =>
      (None, self.showing({ ..content, operation: Sharing(payload.progress), }))
    Published(reply, ..) if content.operation is Sharing(_) => {
      let content = match reply {
        Shared(url~) =>
          {
            ..content,
            operation: Ready,
            publication: Some({ url, copy: Available, }),
          }
        SignInRequired => { ..content, operation: SignInRequired, }
        Failed(message~) => { ..content, operation: Failed(message), }
      }
      (None, self.showing(content))
    }
    SignedIn(result, ..) if content.operation is SigningIn => {
      let operation = match result {
        Ok(_) => Ready
        // Keep the command's diagnostic while retaining the sign-in retry action.
        Err(message) => SignInFailed(message)
      }
      (None, self.showing({ ..content, operation, }))
    }
    ClipboardFinished(result, ..) if content.publication is Some(publication) => {
      let copy = match result {
        Ok(_) => Copied
        Err(message) => Failed(message)
      }
      (
        None,
        self.showing({ ..content, publication: Some({ ..publication, copy, }), }),
      )
    }
    _ => (None, self)
  }
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
/// Native browser panels must hide while this modal owns the screen.
pub fn Model::is_open(self : Model) -> Bool {
  self.visible
}

///|
pub fn Model::open_cloud(self : Model, session~ : String) -> (@cmd.Cmd, Model) {
  (
    @dialog.show(self.id_prefix + "-dialog"),
    {
      ..self,
      generation: self.generation + 1,
      visible: true,
      content: Some({
        source: Cloud(session~),
        operation: Ready,
        publication: None,
      }),
    },
  )
}

///|
/// Login returns to confirmation; an account change retires every pending
/// export reply and published link from the old account.
pub fn Model::account_changed(
  self : Model,
  result : Result[Unit, String],
) -> (@cmd.Cmd, Model) {
  if self.content is Some({ operation: SigningIn, .. }) {
    self.update(_ => @cmd.none, SignedIn(generation=self.generation, result))
  } else if result is Ok(_) &&
    self.content is Some({ source: Host(_, _), operation: SignInRequired, .. }) {
    (@cmd.none, { ..self, generation: self.generation + 1, })
  } else if result is Ok(_) {
    (
      @dialog.close(self.id_prefix + "-dialog"),
      {
        ..self,
        generation: self.generation + 1,
        visible: false,
        content: None,
      },
    )
  } else {
    (@cmd.none, self)
  }
}

///|
pub fn Model::account_expired(self : Model, msg : Msg) -> Bool {
  self.content is Some({ operation: Sharing(_) | Downloading, .. }) &&
  msg is Published(generation~, @protocol.SignInRequired) &&
  generation == self.generation
}

///|
fn Model::file_pending(self : Model) -> Bool {
  self.content is Some({ source: File(_), operation: Sharing(_), .. })
}

///|
fn Model::reopen(self : Model) -> (@cmd.Cmd, Model) {
  (@dialog.show(self.id_prefix + "-dialog"), { ..self, visible: true, })
}

///|
pub fn Model::open_file(self : Model, source : FileSource) -> (@cmd.Cmd, Model) {
  if self.file_pending() ||
    (
      !self.visible &&
      self.content is Some({ source: File(previous), .. }) &&
      previous == source
    ) {
    return self.reopen()
  }
  (
    @dialog.show(self.id_prefix + "-dialog"),
    {
      ..self,
      generation: self.generation + 1,
      visible: true,
      content: Some({
        source: File(source),
        operation: Ready,
        publication: None,
      }),
    },
  )
}

///|
pub extend FileSource with Eq::{equal, not_equal}

///|
pub extend FileSource with Debug::{to_repr}

///|
test "conversation sharing returns from sign-in to confirmation and upload failure permits explicit retry or download" {
  let payload : @protocol.SessionExportPayload = {
    session: "a",
    workspace: "/workspace",
    title: "A",
    archived: false,
  }
  let account : @protocol.AccountSession = {
    token: "ts_fixture",
    user: { user_id: "123", login: "octocat", avatar_url: "", },
  }
  let (_, opened) = Model().open(payload)
  let (effect, needs_login) = opened.transition(Share)
  assert_true(effect is None)
  assert_true(needs_login.content is Some({ operation: SignInRequired, .. }))
  let (effect, signing_in) = needs_login.transition(SignIn)
  assert_true(effect is Some(StartSignIn))
  let (effect, duplicate) = signing_in.transition(SignIn)
  assert_true(effect is None && duplicate == signing_in)
  let (effect, ready) = signing_in.transition(
    SignedIn(generation=signing_in.generation, Ok(())),
  )
  assert_true(effect is None)
  assert_true(
    ready.content is Some({ operation: Ready, publication: None, .. }),
  )
  let (effect, uploading) = ready.transition(Share, account~)
  guard effect is Some(ShareSource(Host(Local, sent), captured)) else {
    fail("only explicit Share should plan the upload")
  }
  assert_eq(sent, payload)
  assert_true(captured == account)
  let (effect, duplicate) = uploading.transition(Share, account~)
  assert_true(effect is None && duplicate == uploading)
  let (effect, failed) = uploading.transition(
    Published(
      generation=uploading.generation,
      Failed(message="Sharing is unavailable on this server."),
    ),
  )
  assert_true(effect is None)
  assert_true(
    failed.content
    is Some({ operation: Failed("Sharing is unavailable on this server."), .. }),
  )
  let (effect, retry) = failed.transition(Share, account~)
  assert_true(effect is Some(ShareSource(Host(Local, _), _)))
  assert_true(retry.generation > uploading.generation)
  let (effect, downloading) = failed.transition(Download)
  assert_true(effect is Some(DownloadSource(Host(Local, _))))
  assert_true(downloading.content is Some({ operation: Downloading, .. }))
}

///|
test "sign-in failure preserves its cause and retry never plans an upload" {
  let (_, opened) = Model().open({
    session: "a",
    workspace: "/workspace",
    title: "A",
    archived: false,
  })
  let (_, needs_login) = opened.transition(Share)
  let (effect, signing_in) = needs_login.transition(SignIn)
  assert_true(effect is Some(StartSignIn))
  let failure = SignedIn(
    generation=signing_in.generation,
    Err("TLS certificate verification failed"),
  )
  let (effect, failed) = signing_in.transition(failure)
  let (repeated_effect, repeated) = signing_in.transition(failure)
  assert_true(effect is None && repeated_effect is None && failed == repeated)
  guard failed.content is Some({ operation: SignInFailed(message), .. }) else {
    fail("the sign-in diagnostic must keep its retry action")
  }
  assert_eq(message, "TLS certificate verification failed")
  let description = dynamic_text(English, DSignInFailure(message.to_string()))
  assert_true(description.contains(message))
  assert_true(
    description.contains(
      "You can try signing in again, or download this conversation.",
    ),
  )
  let (effect, downloading) = failed.transition(Download)
  assert_true(effect is Some(DownloadSource(_)))
  assert_true(downloading.content is Some({ operation: Downloading, .. }))
  let (effect, retry) = failed.transition(SignIn)
  assert_true(effect is Some(StartSignIn))
  let (effect, ready) = retry.transition(
    SignedIn(generation=retry.generation, Ok(())),
  )
  assert_true(effect is None)
  assert_true(
    ready.content is Some({ operation: Ready, publication: None, .. }),
  )
}

///|
test "Cloud export failures retain their source and permit only an explicit retry" {
  let account : @protocol.AccountSession = {
    token: "ts_fixture",
    user: { user_id: "123", login: "octocat", avatar_url: "", },
  }
  let (_, opened) = Model().open_cloud(session="cloud-a")
  for
    message in [
      "This conversation has no complete original log to export.", "Cloud answered HTTP 503. Try again.",
      "Cloud returned an invalid response. Try again.", "Cloud is unreachable. Check your connection and try again.",
    ] {
    let (effect, pending) = opened.transition(Download, account~)
    assert_true(effect is Some(DownloadSource(Cloud(session="cloud-a"))))
    let reply = Downloaded(generation=pending.generation, Err(message))
    let (effect, failed) = pending.transition(reply, account~)
    assert_true(effect is None)
    assert_true(failed.is_open())
    assert_true(
      failed.content
      is Some(
        {
          source: Cloud(session="cloud-a"),
          operation: Failed(reason),
          publication: None,
        }
      ) &&
      reason == message,
    )
    assert_false(pending.account_expired(reply))
    let (effect, ignored) = failed.transition(reply, account~)
    assert_true(effect is None && ignored == failed)
    let (effect, retry) = failed.transition(Download, account~)
    assert_true(effect is Some(DownloadSource(Cloud(session="cloud-a"))))
    assert_true(retry.content is Some({ operation: Downloading, .. }))
  }
  for
    message in [
      "This conversation has no complete original log to export.", "Cloud answered HTTP 503. Try again.",
    ] {
    let (_, pending) = opened.transition(Share, account~)
    let reply = Published(generation=pending.generation, Failed(message~))
    let (effect, failed) = pending.transition(reply, account~)
    assert_true(effect is None && failed.is_open())
    assert_false(pending.account_expired(reply))
    assert_true(
      failed.content
      is Some(
        {
          source: Cloud(session="cloud-a"),
          operation: Failed(reason),
          publication: None,
        }
      ) &&
      reason == message,
    )
    let (effect, retry) = failed.transition(Share, account~)
    assert_true(
      effect is Some(ShareSource(Cloud(session="cloud-a"), captured)) &&
      captured == account,
    )
    assert_eq(retry.generation, pending.generation + 1)
  }
}
