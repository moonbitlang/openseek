///|
/// The last shared stat result, either displayed or waiting for an in-flight
/// navigation to finish. No filesystem work or timer belongs to this model.
enum FileObservation {
  Current(@protocol.FileSignature)
  Pending(@protocol.FileSignature)
} derive(Eq)

///|
pub extend FileObservation with Eq::{equal, not_equal}

///|
fn PageState::local_file(self : PageState) -> @common.Uri? {
  self.url
  .bind(@uri.local_file_path)
  .bind(path => @resource.of_path(@interop.ChannelId::Local, path))
}

///|
fn State::with_page(self : State, id : Int, page : PageState) -> State {
  let pages = self.pages.copy()
  pages[id] = page
  let files = if self.pages.get(id).bind(page => page.local_file()) !=
    page.local_file() {
    let files = self.files.copy()
    files.remove(id)
    files
  } else {
    self.files
  }
  { ..self, pages, files, }
}

///|
/// Feed the same device-bound identities into the editor's watch/stat batch.
pub fn State::local_files(self : State) -> Array[@common.Uri] {
  let paths = []
  for page in self.pages.values() {
    if page.local_file() is Some(path) && !paths.contains(path) {
      paths.push(path)
    }
  }
  paths
}

///|
/// Initial observations and failed reload commands are retried by the shared
/// stat timer, including files already covered by the workspace watcher.
pub fn State::files_to_check(self : State) -> Array[@common.Uri] {
  let paths = []
  for id, page in self.pages {
    if (
        self.files.get(id) is None ||
        self.files.get(id) is Some(Current(Failed(_)))
      ) &&
      page.local_file() is Some(path) &&
      !paths.contains(path) {
      paths.push(path)
    }
  }
  paths
}

///|
/// Consume the shared fs.stat_files result for one local file. The first
/// observation also refreshes once, closing the load-to-first-stat gap.
pub fn State::observe_file(
  self : State,
  path : @common.Uri,
  signature : @protocol.FileSignature,
) -> State {
  let files = self.files.copy()
  let pages = self.pages.copy()
  for id, page in self.pages {
    guard page.local_file() == Some(path) else { continue }
    if signature is Failed(message) {
      files[id] = Current(signature)
      pages[id] = { ..page, failure: Some(message), }
    } else if files.get(id) != Some(Current(signature)) {
      files[id] = Pending(signature)
    }
  }
  { ..self, files, pages, }
}

///|
/// Return refresh actions after loading settles, coalescing changes received
/// during a load. Accept before issuing the command so repeated stats cannot
/// start duplicate reloads. The root owns the native browser commands.
pub fn State::take_file_reloads(self : State) -> (State, Array[Int]) {
  let files = self.files.copy()
  let pages = self.pages.copy()
  let reloads = []
  for id, page in self.pages {
    if !page.loading &&
      page.local_file() is Some(_) &&
      files.get(id) is Some(Pending(signature)) {
      files[id] = Current(signature)
      pages[id] = { ..page, loading: true, failure: None, }
      reloads.push(id)
    }
  }
  ({ ..self, files, pages, }, reloads)
}
