// The in-app folder picker's own state machine, owned by the shell like
// Quick Open: the root model holds one `State?`, and every picker
// transition (open, navigate, listing replies, confirm, close) happens
// here. The shell decides when the picker may open at all and what a
// confirmed directory does — this package only reports the picked location
// back, the way the palette reports an accepted row.

///|
/// The in-app folder picker's state: the host location currently shown and
/// the rows inside it — a directory's subdirectories, or the Windows drive
/// list's drives. `loading` marks a browse or folder creation in flight; a
/// failed operation pops a toast while the previous listing stays usable.
/// `channel` selects the host for browsing and the eventual project mutation;
/// `request_id` is the UUID of the latest request. Only the UUID rides on
/// replies, so a superseded navigation or a closed picker cannot replace the
/// current listing.
///
/// Opaque outside this package: the shell holds the value but cannot read
/// into it — every transition goes through `open`, `handle`, `view`, or
/// `subscriptions`.
struct State {
  channel : @interop.ChannelId
  // The last location the host successfully listed. `None` only while the
  // initial home listing is in flight.
  location : Location?
  entries : Array[String]
  loading : Bool
  // `Some` renders the inline new-folder composer. Its value stays present
  // across a failed create so the user can correct it without retyping.
  new_folder : String?
  // `Some` replaces the breadcrumb with an editable path. Suggestions are
  // derived locally from `entries`; typing a separator after an exact child
  // commits that directory without waiting for a separate Enter press.
  path_draft : String?
  path_selection : Int
  request_id : String
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
/// The fence expected by the current host reply. Exposed with the otherwise
/// opaque state so black-box adapters can drive the state machine directly.
pub fn State::request_id(self : State) -> String {
  self.request_id
}

///|
/// Where the picker's current listing was taken: the raw protocol path of a
/// real host directory — the only thing Confirm can register — or the
/// Windows-only virtual level above the drive roots. Keeping the host path
/// here avoids conflating distinct POSIX paths through URI canonicalization.
pub(all) enum Location {
  Directory(String)
  DriveList
} derive(Eq)

///|
pub extend Location with Eq::{equal, not_equal}

///|
pub(all) enum Msg {
  // Browse into a directory: a subdirectory row, a breadcrumb ancestor, or
  // a path pasted while the picker is open.
  Navigate(String)
  // One location's listing came back from the host — a directory, or the
  // Windows drive list; `request_id` names the browse request it answers,
  // so a stale reply is dropped.
  Loaded(location~ : Location, entries~ : Array[String], request_id~ : String)
  // A browse or create failed; the shell pops the message as a toast and the
  // previous listing stays usable.
  Failed(message~ : String, request_id~ : String)
  // Edit and submit a path in place of the breadcrumb. Matching rows and
  // separator-committed children come only from the directory listing already
  // held by this state.
  EditPath
  PathChanged(String)
  MovePathSelection(Int)
  CompletePath
  SubmitPath
  CancelPathEdit
  // Keyboard Escape cancels an active path edit; otherwise it closes.
  Escape
  // Open, edit, cancel, and submit the inline new-folder composer. Creation
  // enters the new directory by delivering the same `Loaded` reply as browse.
  BeginCreateFolder
  NewFolderNameChanged(String)
  CancelCreateFolder
  CreateFolder
  // Register the picker's current directory and close it.
  Confirm
  Close
} derive(Eq)

///|
pub extend Msg with Eq::{equal, not_equal}

///|
/// What the shell must do about a handled message: register a confirmed
/// directory on its owning device, or surface a request failure as a
/// toast. Everything else stays inside the package.
pub enum Outcome {
  Picked(@interop.ChannelId, String)
  Failed(String)
}

///|
fn State::resume_path_edit_after_render(self : State) -> @cmd.Cmd {
  if self.path_draft is Some(_) {
    focus_path_after_render(false)
  } else {
    @cmd.none
  }
}

///|
/// Open a fresh picker against one device's host, browsing from that host's
/// home directory.
pub fn State::open(
  channel : @interop.ChannelId,
  emit : @cmd.Emit[Msg],
) -> (@cmd.Cmd, State) {
  let request_id = @uuid.mint()
  let picker : State = {
    channel,
    location: None,
    entries: [],
    loading: true,
    new_folder: None,
    path_draft: None,
    path_selection: 0,
    request_id,
  }
  (browse(emit, channel, "", request_id~), picker)
}

///|
/// Fold one picker message into the state. A `Some` outcome is a directory
/// the user registered (the picker has already closed itself) or a
/// navigation failure the shell should surface as a toast.
pub fn State::handle(
  self : State,
  emit : @cmd.Emit[Msg],
  msg : Msg,
) -> (@cmd.Cmd, State?, Outcome?) {
  match msg {
    Navigate(path) => self.navigate_to(emit, path)
    Loaded(location~, entries~, request_id~) =>
      // A listing for a picker the user already closed — or one answering
      // a navigation that has since been superseded — is dropped.
      if request_id == self.request_id {
        (
          self.resume_path_edit_after_render(),
          Some({
            ..self,
            location: Some(location),
            entries,
            loading: false,
            new_folder: None,
            // A separator-committed browse keeps editing with the canonical
            // path the host actually listed, avoiding a second request when
            // the user immediately presses Enter.
            path_draft: self.path_draft.map(_ => {
              match location {
                Directory(path) =>
                  path + (if path.has_suffix("/") { "" } else { "/" })
                DriveList => "/"
              }
            }),
            path_selection: 0,
          }),
          None,
        )
      } else {
        (@cmd.none, Some(self), None)
      }
    Failed(message~, request_id~) =>
      // The failure pops as a toast while the previous listing stays usable.
      // One answering a superseded request stays silent: its toast would
      // describe an operation the user has already replaced.
      if request_id == self.request_id {
        let message = if self.new_folder is Some(_) {
          "Cannot create folder: \{message}"
        } else {
          "Cannot open folder: \{message}"
        }
        (
          self.resume_path_edit_after_render(),
          Some({ ..self, loading: false, }),
          Some(Failed(message)),
        )
      } else {
        (@cmd.none, Some(self), None)
      }
    EditPath =>
      if !self.loading && self.new_folder is None && self.path_draft is None {
        (
          focus_path_after_render(true),
          Some({
            ..self,
            path_draft: Some(self.editable_path()),
            path_selection: 0,
          }),
          None,
        )
      } else if !self.loading &&
        self.new_folder is None &&
        self.path_draft is Some(_) {
        (focus_path_after_render(true), Some(self), None)
      } else {
        (@cmd.none, Some(self), None)
      }
    PathChanged(value) =>
      if !self.loading && self.path_draft is Some(_) {
        let changed = { ..self, path_draft: Some(value), path_selection: 0, }
        match changed.committed_child_path(value) {
          Some(path) => changed.navigate_to(emit, path, path_draft=path)
          None => (@cmd.none, Some(changed), None)
        }
      } else {
        (@cmd.none, Some(self), None)
      }
    MovePathSelection(delta) =>
      if !self.loading && self.path_draft is Some(_) {
        let next = self.move_path_selection(delta)
        let command = if next.path_selection == self.path_selection {
          @cmd.none
        } else {
          scroll_path_row_after_render(next.path_selection)
        }
        (command, Some(next), None)
      } else {
        (@cmd.none, Some(self), None)
      }
    CompletePath =>
      match self.selected_path_suggestion() {
        Some(name) if !self.loading =>
          (
            @cmd.none,
            Some({
              ..self,
              path_draft: Some(self.entry_target(name)),
              path_selection: 0,
            }),
            None,
          )
        _ => (@cmd.none, Some(self), None)
      }
    SubmitPath =>
      match self.path_destination() {
        Some(path) if !self.loading => {
          let already_loaded = match self.location {
            // A trailing separator does not change a directory. Everything
            // else stays exact; the host decides whether alternate casing is
            // equivalent on its platform.
            Some(Directory(current)) =>
              current == path ||
              (
                current != "/" &&
                current.trim_end(chars="/") == path.trim_end(chars="/")
              )
            Some(DriveList) => path.trim() == "/"
            None => false
          }
          if already_loaded {
            (
              @cmd.none,
              Some({ ..self, path_draft: None, path_selection: 0, }),
              None,
            )
          } else {
            self.navigate_to(emit, path)
          }
        }
        _ => (@cmd.none, Some(self), None)
      }
    CancelPathEdit | Escape if self.path_draft is Some(_) => {
      // Separator completion may have started a browse while the editor is
      // still visible. Cancelling must also fence that request; otherwise its
      // late reply would move the picker after the edit was discarded.
      let request_id = @uuid.mint()
      (
        @cmd.none,
        Some({
          ..self,
          loading: false,
          path_draft: None,
          path_selection: 0,
          request_id,
        }),
        None,
      )
    }
    CancelPathEdit => (@cmd.none, Some(self), None)
    Escape => (@cmd.none, None, None)
    BeginCreateFolder =>
      if self.location is Some(Directory(_)) &&
        !self.loading &&
        self.path_draft is None {
        (@cmd.none, Some({ ..self, new_folder: Some(""), }), None)
      } else {
        (@cmd.none, Some(self), None)
      }
    NewFolderNameChanged(name) =>
      if self.new_folder is Some(_) && !self.loading {
        (@cmd.none, Some({ ..self, new_folder: Some(name), }), None)
      } else {
        (@cmd.none, Some(self), None)
      }
    CancelCreateFolder =>
      if self.loading {
        (@cmd.none, Some(self), None)
      } else {
        (@cmd.none, Some({ ..self, new_folder: None, }), None)
      }
    CreateFolder =>
      match (self.location, self.new_folder) {
        (Some(Directory(parent)), Some(name)) if !self.loading &&
          !name.trim().is_empty() => {
          let request_id = @uuid.mint()
          (
            create_folder(
              emit,
              self.channel,
              parent,
              name.trim().to_owned(),
              request_id~,
            ),
            Some({ ..self, loading: true, request_id, }),
            None,
          )
        }
        _ => (@cmd.none, Some(self), None)
      }
    Confirm =>
      // Register the directory the host last listed — always something it
      // confirmed exists — never raw pasted text; a paste navigates (and
      // validates) first. While a navigation is in flight the shown listing
      // is stale, so Enter must wait: confirming then would attach the
      // previous directory, not the destination. The Windows drive list is
      // not a directory and cannot be registered.
      if self.location is Some(Directory(path)) &&
        !self.loading &&
        self.new_folder is None &&
        self.path_draft is None {
        (@cmd.none, None, Some(Picked(self.channel, path)))
      } else {
        (@cmd.none, Some(self), None)
      }
    Close => (@cmd.none, None, None)
  }
}

///|
/// Start every path transition through one stale-reply fence. Ordinary
/// navigation clears the editor; separator completion passes the host-returned
/// protocol path back as the next draft so editing can continue after reply.
fn State::navigate_to(
  self : State,
  emit : @cmd.Emit[Msg],
  path : String,
  path_draft? : String,
) -> (@cmd.Cmd, State?, Outcome?) {
  let request_id = @uuid.mint()
  (
    browse(emit, self.channel, path, request_id~),
    Some({
      ..self,
      loading: true,
      new_folder: None,
      path_draft,
      path_selection: 0,
      request_id,
    }),
    None,
  )
}
