// Resolve the local project that owns each Codex thread cwd. App-server owns
// threads and reports only their exact working directories; Git owns the
// relationship between the local checkout and Codex-managed worktrees.

///|
/// Process-local cache from an existing checkout path to its main Git worktree.
/// Missing paths are deliberately absent: a later catalog refresh must probe
/// again after an external volume is mounted or a worktree is recreated.
struct ProjectCatalog {
  roots : Map[String, String]
  // A project becomes selectable only after an authoritative app-server
  // thread/list or thread/read reply names a cwd that Git maps to it.
  known_projects : Map[String, Bool]
}

///|
pub fn ProjectCatalog::ProjectCatalog() -> ProjectCatalog {
  { roots: Map([]), known_projects: Map([]), }
}

///|
/// Record every checkout printed by one `git worktree list --porcelain` call.
/// Git prints the main worktree first, so every following linked worktree maps
/// back to that same project. The queried cwd is cached separately because a
/// thread may start in a subdirectory rather than at the checkout root.
fn ProjectCatalog::record_worktrees(
  self : ProjectCatalog,
  cwd : String,
  output : String,
) -> String? {
  let worktrees : Array[String] = []
  for line in output.split("\n") {
    if line.strip_prefix("worktree ") is Some(path) {
      let path = path.trim_end(chars="\r").to_owned()
      if !path.is_empty() {
        worktrees.push(path)
      }
    }
  }
  guard worktrees.get(0) is Some(project) else { return None }
  for worktree in worktrees {
    self.roots[worktree] = project
  }
  self.roots[cwd] = project
  Some(project)
}

///|
/// Resolve one app-server cwd without interpreting Codex's managed-worktree
/// path convention. Git's own worktree catalog is authoritative and also
/// handles worktree roots configured outside `$CODEX_HOME`.
async fn ProjectCatalog::resolve(
  self : ProjectCatalog,
  cwd : String,
) -> String? {
  if self.roots.get(cwd) is Some(cached) {
    return Some(cached)
  }
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    "git",
    ["worktree", "list", "--porcelain"],
    cwd~,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      let root = if @fs.exists(cwd) { Some(cwd) } else { None }
      if root is Some(root) {
        self.roots[cwd] = root
      }
      return root
    }
  }
  if code == 0 {
    let output = stdout.text() catch { _ => "" }
    if self.record_worktrees(cwd, output) is Some(project) {
      return Some(project)
    }
  }
  let root = if @fs.exists(cwd) { Some(cwd) } else { None }
  if root is Some(root) {
    self.roots[cwd] = root
  }
  root
}

///|
/// Confirm that an add action names a project previously learned from an
/// app-server thread reply. Existence alone is not authority: a remote page
/// must not turn an arbitrary directory spelling into a Desktop grant.
pub fn ProjectCatalog::main_project(
  self : ProjectCatalog,
  cwd : String,
) -> String? {
  let cwd = cwd.trim().to_owned()
  if self.known_projects.get(cwd) == Some(true) {
    Some(cwd)
  } else {
    None
  }
}

///|
/// Add OpenSeek's `projectRoot` extension to one app-server thread object.
/// All original app-server fields stay byte-for-byte equivalent as JSON data;
/// an unavailable/deleted cwd is left without a project instead of being
/// promoted to a misleading top-level worktree.
async fn ProjectCatalog::annotate_thread(
  self : ProjectCatalog,
  value : Json,
) -> Json {
  guard value is Object(thread) else { return value }
  let annotated = thread.copy()
  if thread.get("cwd") is Some(String(cwd)) &&
    !cwd.trim().is_empty() &&
    self.resolve(cwd) is Some(project) {
    annotated["projectRoot"] = Json(project)
    self.known_projects[project] = true
  }
  Json(annotated)
}

///|
/// Enrich both thread catalogs (`data`) and single-thread replies (`thread`).
/// Keeping this at the native Codex boundary means every frontend receives the
/// same project identity and never has to execute Git or recognize worktree
/// directory names.
pub async fn ProjectCatalog::annotate(
  self : ProjectCatalog,
  reply : Json,
) -> Json {
  guard reply is Object(fields) else { return reply }
  let annotated = fields.copy()
  if fields.get("data") is Some(Array(threads)) {
    let data : Array[Json] = []
    for thread in threads {
      data.push(self.annotate_thread(thread))
    }
    annotated["data"] = Json(data)
  }
  if fields.get("thread") is Some(thread) {
    annotated["thread"] = self.annotate_thread(thread)
  }
  Json(annotated)
}

///|
test "Codex project catalog maps every linked worktree to the main checkout" {
  let catalog = ProjectCatalog()
  let root = catalog.record_worktrees(
    "/Users/me/.codex/worktrees/47b9/openseek", "worktree /Users/me/src/openseek\nHEAD abc\n\nworktree /Users/me/.codex/worktrees/47b9/openseek\nHEAD def\n\nworktree /Users/me/.codex/worktrees/dd8c/openseek\nHEAD ghi\n",
  )
  assert_eq(root, Some("/Users/me/src/openseek"))
  assert_eq(
    catalog.roots.get("/Users/me/.codex/worktrees/dd8c/openseek"),
    Some("/Users/me/src/openseek"),
  )
}

///|
async test "Codex project catalog rechecks a missing cwd on later refreshes" {
  let catalog = ProjectCatalog()
  let missing = ".openseek-codex-project-catalog-missing-cwd"
  if @fs.exists(missing) {
    fail("reserved missing-cwd test path unexpectedly exists")
  }
  assert_eq(catalog.resolve(missing), None)
  // Absence, rather than a cached negative value, makes the next resolve run
  // the filesystem/Git probe again.
  assert_true(catalog.roots.get(missing) is None)
}

///|
async test "Codex draft projects accept only the main checkout" {
  let catalog = ProjectCatalog()
  catalog.roots["/workspace/project"] = "/workspace/project"
  catalog.roots["/worktrees/a/project"] = "/workspace/project"
  // A cached filesystem lookup alone is not enough to grant a browser path.
  assert_true(catalog.main_project("/workspace/project") is None)
  catalog.known_projects["/workspace/project"] = true
  assert_eq(
    catalog.main_project("/workspace/project"),
    Some("/workspace/project"),
  )
  assert_true(catalog.main_project("/worktrees/a/project") is None)
}

///|
async test "Codex thread replies retain cwd and receive cached project roots" {
  let catalog = ProjectCatalog()
  catalog.roots["/worktrees/a/project"] = "/workspace/project"
  let annotated = catalog.annotate({
    "data": [
      { "id": "thread-a", "cwd": "/worktrees/a/project", "preview": "First" },
    ],
  })
  guard annotated is Object(fields) &&
    fields.get("data") is Some(Array([Object(thread)])) else {
    fail("expected annotated thread list")
  }
  assert_eq(thread.get("projectRoot"), Some(Json("/workspace/project")))
  assert_eq(thread.get("cwd"), Some(Json("/worktrees/a/project")))
}
