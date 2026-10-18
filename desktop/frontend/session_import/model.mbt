///|
const DialogId = "session-import-dialog"

///|
struct Model {
  generation : Int32
  content : Content?
} derive(Eq, Debug)

///|
pub(all) enum Workspace {
  Unplaced
  Allocated(String)
  Registered(String)
} derive(Eq, Debug)

///|
pub(all) struct Target {
  channel : @interop.ChannelId
  connection_generation : Int32
  workspace : Workspace
  worktree_of : String?
} derive(Eq, Debug)

///|
priv struct Content {
  target : Target
  link : String
  operation : Operation
} derive(Eq, Debug)

///|
priv enum Operation {
  Ready
  Reading
  Importing
  Failed(String)
} derive(Eq, Debug)

///|
pub(all) enum Msg {
  Close
  PickFile
  LinkChanged(String)
  ImportLink
  Picked(Int32, Result[String?, String])
  WorkspaceChanged(Int32, Workspace)
  Imported(Int32, @protocol.SessionImportReply)
}

///|
pub fn Model::Model() -> Model {
  { generation: 0, content: None, }
}

///|
pub fn Model::is_open(self : Model) -> Bool {
  self.content is Some(_)
}

///|
pub fn Model::open(self : Model, target : Target) -> (@cmd.Cmd, Model) {
  (
    @dialog.show(DialogId),
    {
      generation: self.generation + 1,
      content: Some({ target, link: "", operation: Ready, }),
    },
  )
}

///|
fn Operation::busy(self : Operation) -> Bool {
  self is (Reading | Importing)
}

///|
fn Msg::generation(self : Msg) -> Int32? {
  match self {
    Picked(g, _) | WorkspaceChanged(g, _) | Imported(g, _) => Some(g)
    _ => None
  }
}

///|
pub fn Model::update(
  self : Model,
  emit : @cmd.Emit[Msg],
  msg : Msg,
) -> (@cmd.Cmd, Model, (Target, String)?) {
  guard self.content is Some(content) else { return (@cmd.none, self, None) }
  if msg.generation() is Some(g) && g != self.generation {
    return (@cmd.none, self, None)
  }
  let generation = self.generation + 1
  match msg {
    Close => (@dialog.close(DialogId), { ..self, content: None, }, None)
    LinkChanged(link) =>
      (@cmd.none, { ..self, content: Some({ ..content, link, }), }, None)
    WorkspaceChanged(_, workspace) if content.operation is Importing =>
      (
        @cmd.none,
        {
          ..self,
          content: Some({ ..content, target: { ..content.target, workspace, }, }),
        },
        None,
      )
    PickFile if !content.operation.busy() =>
      (
        pick_file(generation, emit),
        { generation, content: Some({ ..content, operation: Reading, }), },
        None,
      )
    ImportLink if !content.operation.busy() && !content.link.is_blank() =>
      self.import_source(emit, @protocol.ShareLink(url=content.link))
    Picked(_, result) if content.operation is Reading =>
      match result {
        Ok(Some(text)) => self.import_source(emit, @protocol.JsonFile(text~))
        Ok(None) =>
          (
            @cmd.none,
            { ..self, content: Some({ ..content, operation: Ready, }), },
            None,
          )
        Err(message) =>
          (
            @cmd.none,
            {
              ..self,
              content: Some({ ..content, operation: Failed(message), }),
            },
            None,
          )
      }
    Imported(_, reply) if content.operation is Importing =>
      match reply {
        Success(reply) =>
          (
            @dialog.close(DialogId),
            { ..self, content: None, },
            Some((content.target, reply)),
          )
        Failed(message) =>
          (
            @cmd.none,
            {
              ..self,
              content: Some({ ..content, operation: Failed(message), }),
            },
            None,
          )
      }
    _ => (@cmd.none, self, None)
  }
}

///|
fn Model::import_source(
  self : Model,
  emit : @cmd.Emit[Msg],
  source : @protocol.SessionImportSource,
) -> (@cmd.Cmd, Model, (Target, String)?) {
  guard self.content is Some(content) else { return (@cmd.none, self, None) }
  let generation = self.generation + 1
  (
    import_source(content.target, source, generation, emit),
    { generation, content: Some({ ..content, operation: Importing, }), },
    None,
  )
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Target with @debug.Debug::{to_repr}

///|
pub extend Workspace with Eq::{equal, not_equal}

///|
pub extend Workspace with @debug.Debug::{to_repr}
