///|
const DialogId = "conversation-export-dialog"

///|
/// Each opening captures its source and advances a generation. Late replies
/// from a dismissed dialog cannot overwrite a later conversation's dialog.
struct Model {
  generation : Int
  content : Content?
} derive(Eq, Debug)

///|
priv struct Content {
  source : @protocol.SessionExportPayload
  operation : Operation
  // A completed link survives subsequent downloads and their errors.
  publication : Publication?
} derive(Eq, Debug)

///|
priv enum Operation {
  Ready
  Downloading
  Sharing
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
  Downloaded(generation~ : Int, Result[@protocol.SessionExportReply, String])
  Published(generation~ : Int, @protocol.SessionShareReply)
  SignedIn(generation~ : Int, Result[Unit, String])
  ClipboardFinished(generation~ : Int, Result[Unit, String])
}

///|
/// The opening a reply belongs to; user actions always target the current one.
fn Msg::generation(self : Msg) -> Int? {
  match self {
    Downloaded(generation~, _)
    | Published(generation~, _)
    | SignedIn(generation~, _)
    | ClipboardFinished(generation~, _) => Some(generation)
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
) -> (@cmd.Cmd, Model) {
  (
    @dialog.show(DialogId),
    {
      generation: self.generation + 1,
      content: Some({ source, operation: Ready, publication: None, }),
    },
  )
}

///|
fn Operation::busy(self : Operation) -> Bool {
  self is (Downloading | Sharing | SigningIn)
}

///|
fn Model::showing(self : Model, content : Content) -> Model {
  { ..self, content: Some(content), }
}

///|
pub fn Model::update(
  locale? : @i18n.Locale = English,
  self : Model,
  emit : @cmd.Emit[Msg],
  msg : Msg,
) -> (@cmd.Cmd, Model) {
  guard self.content is Some(content) else { return (@cmd.none, self) }
  if msg.generation() is Some(generation) && generation != self.generation {
    return (@cmd.none, self)
  }
  let busy = content.operation.busy()
  match msg {
    Close => {
      // A browser sign-in this dialog started must not outlive it: the host
      // refuses a second auth.connect while one is still waiting.
      let close = @dialog.close(DialogId)
      let cmd = if content.operation is SigningIn {
        @cmd.batch([close, cancel_sign_in()])
      } else {
        close
      }
      (cmd, { ..self, content: None, })
    }
    Download if !busy =>
      (
        self.download(locale~, emit, content.source),
        self.showing({ ..content, operation: Downloading, }),
      )
    Share if !busy && content.publication is None =>
      (
        self.share(locale~, emit, content.source),
        self.showing({ ..content, operation: Sharing, }),
      )
    SignIn if content.operation is (SignInRequired | SignInFailed(_)) =>
      (
        self.sign_in(locale~, emit),
        self.showing({ ..content, operation: SigningIn, }),
      )
    Downloaded(result, ..) if content.operation is Downloading => {
      let operation = match result {
        Ok({ path: Some(path), opened, }) => Saved(path~, opened~)
        Ok({ path: None, .. }) => Ready
        Err(message) => Failed(message)
      }
      (@cmd.none, self.showing({ ..content, operation, }))
    }
    Published(reply, ..) if content.operation is Sharing => {
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
