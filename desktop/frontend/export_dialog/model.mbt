///|
const DialogId = "conversation-export-dialog"

///|
/// Each opening captures its source and advances a generation. Late replies
/// from a dismissed dialog cannot overwrite a later conversation's dialog.
struct Model {
  generation : Int32
  content : Content?
} derive(Eq, Debug)

///|
priv enum Source {
  Host(@interop.ChannelId, @protocol.SessionExportPayload)
} derive(Eq, Debug)

///|
priv struct Content {
  source : Source
  operation : Operation
  // A completed link survives subsequent downloads and their errors.
  publication : Publication?
} derive(Eq, Debug)

///|
priv enum Operation {
  Ready
  Downloading
  Sharing(@protocol.ShareProgress)
  SigningIn
  SignInRequired
  SignInFailed(String)
  Saved(path~ : String, opened~ : Bool)
  Failed(String)
} derive(Eq, Debug)

///|
priv struct Publication {
  url : String
  copy : CopyState
} derive(Eq, Debug)

///|
priv enum CopyState {
  Available
  Copied
  Failed(String)
} derive(Eq, Debug)

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
pub fn Model::Model() -> Model {
  { generation: 0, content: None, }
}

///|
pub fn Model::open(
  self : Model,
  source : @protocol.SessionExportPayload,
  channel~ : @interop.ChannelId = Local,
) -> (@cmd.Cmd, Model) {
  (
    @dialog.show(DialogId),
    {
      generation: self.generation + 1,
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
pub fn Model::update(
  self : Model,
  emit : @cmd.Emit[Msg],
  msg : Msg,
  account? : @protocol.AccountSession,
  desktop~ : Bool = true,
  sign_in~ : @cmd.Cmd = @cmd.none,
) -> (@cmd.Cmd, Model) {
  guard self.content is Some(content) else { return (@cmd.none, self) }
  if msg.generation() is Some(generation) && generation != self.generation {
    return (@cmd.none, self)
  }
  let msg = match msg {
    HostProgress(channel, payload) =>
      match content.source {
        Host(owner, _) if owner == channel => Progress(payload)
        _ => return (@cmd.none, self)
      }
    _ => msg
  }
  let busy = content.operation.busy()
  match msg {
    Close => {
      // A browser sign-in this dialog started must not outlive it: the host
      // refuses a second auth.connect while one is still waiting.
      let close = @dialog.close(DialogId)
      let cmd = if desktop && content.operation is SigningIn {
        @cmd.batch([close, cancel_sign_in()])
      } else {
        close
      }
      (cmd, { ..self, content: None, })
    }
    Download if !busy =>
      (
        self.download(emit, content.source, desktop~),
        self.showing({ ..content, operation: Downloading, }),
      )
    Share if !busy && content.publication is None =>
      if content.source is Host(Remote("host"), _) {
        (
          @cmd.none,
          self.showing({
            ..content,
            operation: Failed(
              "Sharing is unavailable in the local debug console. Use SeekMoonDev.app or the hosted browser console. You can still download this conversation.",
            ),
          }),
        )
      } else {
        match account {
          Some(account) => {
            let next = { ..self, generation: self.generation + 1, }
            (
              next.share(emit, content.source, account, desktop~),
              next.showing({ ..content, operation: Sharing(Preparing), }),
            )
          }
          None =>
            (@cmd.none, self.showing({ ..content, operation: SignInRequired, }))
        }
      }
    SignIn if content.operation is (SignInRequired | SignInFailed(_)) =>
      (sign_in, self.showing({ ..content, operation: SigningIn, }))
    Downloaded(result, ..) if content.operation is Downloading => {
      let operation = match result {
        Ok({ path: Some(path), opened, }) => Saved(path~, opened~)
        Ok({ path: None, .. }) => Ready
        Err(message) => Failed(message)
      }
      (@cmd.none, self.showing({ ..content, operation, }))
    }
    Progress(payload) if content.operation is Sharing(_) =>
      (
        @cmd.none,
        self.showing({ ..content, operation: Sharing(payload.progress), }),
      )
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
      (@cmd.none, self.showing(content))
    }
    SignedIn(result, ..) if content.operation is SigningIn => {
      let operation = match result {
        Ok(_) => Ready
        // Keep the command's diagnostic while retaining the sign-in retry action.
        Err(message) => SignInFailed(message)
      }
      (@cmd.none, self.showing({ ..content, operation, }))
    }
    ClipboardFinished(result, ..) if content.publication is Some(publication) => {
      let copy = match result {
        Ok(_) => Copied
        Err(message) => Failed(message)
      }
      (
        @cmd.none,
        self.showing({ ..content, publication: Some({ ..publication, copy, }), }),
      )
    }
    _ => (@cmd.none, self)
  }
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
/// Native browser panels must hide while this modal owns the screen.
pub fn Model::is_open(self : Model) -> Bool {
  self.content is Some(_)
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
      @dialog.close(DialogId),
      { generation: self.generation + 1, content: None, },
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
