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
  expires_at : String
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
pub fn Model::update(
  self : Model,
  emit : @cmd.Emit[Msg],
  msg : Msg,
) -> (@cmd.Cmd, Model) {
  guard self.content is Some(content) else { return (@cmd.none, self) }
  let generation = self.generation
  let operation = match msg {
    Close => return (@dialog.close(DialogId), { ..self, content: None, })
    Download if !content.operation.busy() =>
      return (
        self.download(emit, content.source),
        { ..self, content: Some({ ..content, operation: Downloading, }), },
      )
    Share if !content.operation.busy() && content.publication is None =>
      return (
        self.share(emit, content.source),
        { ..self, content: Some({ ..content, operation: Sharing, }), },
      )
    SignIn if content.operation is (SignInRequired | SignInFailed(_)) =>
      return (
        self.sign_in(emit),
        { ..self, content: Some({ ..content, operation: SigningIn, }), },
      )
    Downloaded(generation=id, result) if id == generation &&
      content.operation is Downloading =>
      match result {
        Ok({ path: Some(path), opened, }) => Saved(path~, opened~)
        Ok({ path: None, .. }) => Ready
        Err(message) => Failed(message)
      }
    Published(generation=id, reply) if id == generation &&
      content.operation is Sharing =>
      match reply {
        Shared(url~, expires_at~) =>
          return (
            @cmd.none,
            {
              ..self,
              content: Some({
                ..content,
                operation: Ready,
                publication: Some({ url, expires_at, copy: Available, }),
              }),
            },
          )
        SignInRequired => SignInRequired
        Failed(message~) => Failed(message)
      }
    SignedIn(generation=id, result) if id == generation &&
      content.operation is SigningIn =>
      match result {
        Ok(_) => Ready
        // Keep the command's diagnostic while retaining the sign-in retry action.
        Err(message) => SignInFailed(message)
      }
    ClipboardFinished(generation=id, result) if id == generation =>
      match content.publication {
        Some(publication) =>
          return (
            @cmd.none,
            {
              ..self,
              content: Some({
                ..content,
                publication: Some({
                  ..publication,
                  copy: match result {
                    Ok(_) => Copied
                    Err(message) => Failed(message)
                  },
                }),
              }),
            },
          )
        None => return (@cmd.none, self)
      }
    _ => return (@cmd.none, self)
  }
  (@cmd.none, { ..self, content: Some({ ..content, operation, }), })
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
