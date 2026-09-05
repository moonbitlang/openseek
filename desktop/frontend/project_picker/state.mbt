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
/// failed navigation or create pops a toast while the previous listing stays
/// usable, and a failed completion browse shows the host's reason where the
/// rows were.
/// `channel` owns every browse and the eventual project mutation;
/// `generation` numbers that picker's latest request. Both ride on replies,
/// so neither a superseded navigation nor a closed picker from another
/// device can replace the current listing.
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
  // Whether the browsed host itself is Windows — the shell's per-device
  // fact, learned once from `app.info` when the channel connected and fixed
  // for the picker's life. Chooses where a drive-letter draft completes
  // from; never guessed from path shapes.
  windows_host : Bool
  // `Some` renders the inline new-folder composer. Its value stays present
  // across a failed create so the user can correct it without retyping.
  new_folder : String?
  // `Some` replaces the breadcrumb with an editable path. The listing follows
  // the directory the draft names — typing past a separator or deleting back
  // across one browses it while the editor stays open — and its rows narrow
  // by the segment typed after that separator.
  path_draft : String?
  path_selection : Int
  // The draft's most recent completion browse and how it stands — the host
  // is still answering, or refused with its reason — so retyping inside the
  // same directory never repeats the request, and the refusal explains the
  // empty rows in place. A listing clears it: the host may have canonicalized
  // the spelling, and an alias typed again is its to resolve. Cleared with
  // the draft.
  completion_browse : CompletionBrowse?
  generation : Int
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
/// One completion browse from the draft's point of view: the directory it
/// asked the host to list, still unanswered or refused with the host's
/// reason.
priv enum CompletionBrowse {
  Asking(String)
  Refused(String, message~ : String)
} derive(Eq)

///|
fn CompletionBrowse::parent(self : CompletionBrowse) -> String {
  match self {
    Asking(parent) | Refused(parent, ..) => parent
  }
}

///|
/// The fence expected by the current host reply. Exposed with the otherwise
/// opaque state so black-box adapters can drive the state machine directly.
pub fn State::request_generation(self : State) -> Int {
  self.generation
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
  // Windows drive list; `generation` names the browse request it answers,
  // so a stale reply is dropped.
  Loaded(
    channel~ : @interop.ChannelId,
    location~ : Location,
    entries~ : Array[String],
    generation~ : Int
  )
  // A browse or create failed; the shell pops the message as a toast and the
  // previous listing stays usable.
  Failed(channel~ : @interop.ChannelId, message~ : String, generation~ : Int)
  // Edit and submit a path in place of the breadcrumb. The listing follows
  // the directory the draft names so its rows can complete it.
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
/// One process-wide sequence keeps replies from a closed picker from matching
/// a later picker opened on the same channel.
let next_request_generation : Ref[Int] = Ref(0)

///|
fn fresh_request_generation() -> Int {
  next_request_generation.val += 1
  next_request_generation.val
}

///|
/// The directory that "New folder" and Confirm act on, when they may: the
/// host listed a real directory, nothing is in flight, and no composer or
/// path edit names somewhere else. A path edit that still names this
/// directory does not block them; the action closes it.
fn State::actionable_directory(self : State) -> String? {
  if self.location is Some(Directory(path)) &&
    !self.loading &&
    self.new_folder is None &&
    (self.path_draft is None || self.path_draft_names_location()) {
    Some(path)
  } else {
    None
  }
}

///|
/// Open a fresh picker against one device's host, browsing from that host's
/// home directory. `windows` is that host's own platform, from the shell's
/// per-device `app.info` fact.
pub fn State::open(
  channel : @interop.ChannelId,
  emit : @cmd.Emit[Msg],
  windows~ : Bool,
) -> (@cmd.Cmd, State) {
  let generation = fresh_request_generation()
  let picker : State = {
    channel,
    location: None,
    entries: [],
    loading: true,
    windows_host: windows,
    new_folder: None,
    path_draft: None,
    path_selection: 0,
    completion_browse: None,
    generation,
  }
  (browse(emit, channel, "", generation~), picker)
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
    Loaded(channel~, location~, entries~, generation~) =>
      // A listing for a picker the user already closed — or one answering
      // a navigation that has since been superseded — is dropped.
      if channel == self.channel && generation == self.generation {
        let next = {
          ..self,
          location: Some(location),
          entries,
          loading: false,
          new_folder: None,
          completion_browse: None,
          // A completion browse keeps editing with the canonical path the
          // host actually listed — avoiding a second request when the user
          // presses Enter — and the segment the draft was completing.
          path_draft: self
          .completion()
          .map(completion => {
            let (_, segment) = completion
            location.base() + segment
          }),
          path_selection: 0,
        }
        (@cmd.none, Some(next), None)
      } else {
        (@cmd.none, Some(self), None)
      }
    Failed(channel~, message~, generation~) =>
      // The failure pops as a toast while the previous listing stays usable.
      // One answering a superseded request stays silent: its toast would
      // describe an operation the user has already replaced.
      if channel == self.channel && generation == self.generation {
        let next = { ..self, loading: false, }
        if self.new_folder is Some(_) {
          // The composer's input was disabled during the request, which
          // dropped focus; hand it back with the rejected name still there.
          (
            focus_new_folder_after_render(),
            Some(next),
            Some(Failed("Cannot create folder: \{message}")),
          )
        } else if self.path_draft is Some(_) {
          // A completion browse could not list the directory the draft
          // names. The rows show the host's reason in place — permissions,
          // a missing directory, and a non-directory path read differently —
          // while a toast would nag on every keystroke inside a path still
          // being typed.
          let completion_browse = match self.completion_browse {
            Some(Asking(parent) | Refused(parent, ..)) =>
              Some(Refused(parent, message~))
            None => None
          }
          (@cmd.none, Some({ ..next, completion_browse, }), None)
        } else {
          (
            @cmd.none,
            Some(next),
            Some(Failed("Cannot open folder: \{message}")),
          )
        }
      } else {
        (@cmd.none, Some(self), None)
      }
    EditPath =>
      if !self.loading && self.new_folder is None && self.path_draft is None {
        (
          focus_path_after_render(),
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
        (focus_path_after_render(), Some(self), None)
      } else {
        (@cmd.none, Some(self), None)
      }
    PathChanged(value) =>
      // The editor stays enabled through its own completion browses, so a
      // keystroke may arrive while one is in flight; the fence below or a
      // fresh request supersedes it.
      if self.path_draft is Some(_) {
        let changed = { ..self, path_draft: Some(value), path_selection: 0, }
        match changed.completion() {
          Some((parent, _)) if changed.already_loaded(parent) =>
            // Back inside the listed directory. A parent browse still in
            // flight must not move the picker when it answers.
            if changed.loading {
              (
                @cmd.none,
                Some({
                  ..changed,
                  loading: false,
                  completion_browse: None,
                  generation: fresh_request_generation(),
                }),
                None,
              )
            } else {
              (@cmd.none, Some(changed), None)
            }
          Some((parent, _)) if changed.completion_browse is Some(asked) &&
            asked.parent() == parent =>
            // Already asked: its listing is on the way, or the host could
            // not provide one.
            (@cmd.none, Some(changed), None)
          Some((parent, segment)) =>
            changed.complete_from(emit, parent, segment)
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
      // Enter during a completion browse still navigates: the fresh request
      // supersedes the listing that was only meant to complete the draft.
      match self.path_destination() {
        Some(path) =>
          if self.already_loaded(path) {
            (
              @cmd.none,
              Some({
                ..self,
                path_draft: None,
                path_selection: 0,
                completion_browse: None,
              }),
              None,
            )
          } else {
            self.navigate_to(emit, path)
          }
        None => (@cmd.none, Some(self), None)
      }
    CancelPathEdit | Escape if self.path_draft is Some(_) => {
      // A completion browse may still be in flight while the editor is
      // visible. Cancelling must also fence that request; otherwise its late
      // reply would move the picker after the edit was discarded.
      let generation = fresh_request_generation()
      (
        @cmd.none,
        Some({
          ..self,
          loading: false,
          path_draft: None,
          path_selection: 0,
          completion_browse: None,
          generation,
        }),
        None,
      )
    }
    CancelPathEdit => (@cmd.none, Some(self), None)
    Escape => (@cmd.none, None, None)
    BeginCreateFolder =>
      // The composer replaces a path edit that still names this directory.
      // Its input is focused explicitly: the click leaves the button focused,
      // so the browser ignores the input's `autofocus`.
      if self.actionable_directory() is Some(_) {
        (
          focus_new_folder_after_render(),
          Some({
            ..self,
            new_folder: Some(""),
            path_draft: None,
            path_selection: 0,
            completion_browse: None,
          }),
          None,
        )
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
          let generation = fresh_request_generation()
          (
            create_folder(
              emit,
              self.channel,
              parent,
              name.trim().to_owned(),
              generation~,
            ),
            Some({ ..self, loading: true, generation, }),
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
      // previous directory, not the destination. A path edit naming another
      // directory must wait the same way; one still naming the listed
      // directory is discarded. The Windows drive list is not a directory
      // and cannot be registered.
      if self.actionable_directory() is Some(path) {
        (@cmd.none, None, Some(Picked(self.channel, path)))
      } else {
        (@cmd.none, Some(self), None)
      }
    Close => (@cmd.none, None, None)
  }
}

///|
/// Start a navigation through one stale-reply fence, closing the path editor
/// and the composer: the destination is what the user chose, not a
/// completion.
fn State::navigate_to(
  self : State,
  emit : @cmd.Emit[Msg],
  path : String,
) -> (@cmd.Cmd, State?, Outcome?) {
  let generation = fresh_request_generation()
  (
    browse(emit, self.channel, path, generation~),
    Some({
      ..self,
      loading: true,
      new_folder: None,
      path_draft: None,
      path_selection: 0,
      completion_browse: None,
      generation,
    }),
    None,
  )
}

///|
/// Browse the directory the draft names so its rows can complete it, keeping
/// the editor open on the draft's absolute form. The reply rewrites the
/// directory part to the path the host listed and keeps `segment`.
fn State::complete_from(
  self : State,
  emit : @cmd.Emit[Msg],
  parent : String,
  segment : String,
) -> (@cmd.Cmd, State?, Outcome?) {
  let generation = fresh_request_generation()
  (
    browse(emit, self.channel, parent, generation~),
    Some({
      ..self,
      loading: true,
      path_draft: Some(parent + segment),
      path_selection: 0,
      completion_browse: Some(Asking(parent)),
      generation,
    }),
    None,
  )
}
