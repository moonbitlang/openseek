// Resolve the local project that owns each Codex thread cwd. App-server owns
// threads and reports only their exact working directories; Git owns the
// relationship between the local checkout and Codex-managed worktrees.

///|
/// Process-local cache from a checkout path to its main Git worktree. A cached
/// `None` records a cwd that no longer exists; an existing non-Git directory
/// maps to itself and remains a normal standalone project.
struct ProjectCatalog {
  roots : Map[String, String?]
}

///|
pub fn ProjectCatalog::ProjectCatalog() -> ProjectCatalog {
  { roots: Map([]) }
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
    self.roots[worktree] = Some(project)
  }
  self.roots[cwd] = Some(project)
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
    return cached
  }
  let (code, stdout, _) = @process.collect_output(
    "git",
    ["worktree", "list", "--porcelain"],
    cwd~,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      let root = if @fs.exists(cwd) { Some(cwd) } else { None }
      self.roots[cwd] = root
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
  self.roots[cwd] = root
  root
}

///|
/// Confirm that an add action names the main project itself, rather than one
/// of that project's linked worktrees or an arbitrary subdirectory. A
/// standalone non-Git directory resolves to itself and remains supported.
pub async fn ProjectCatalog::main_project(
  self : ProjectCatalog,
  cwd : String,
) -> String? {
  let cwd = cwd.trim().to_owned()
  guard !cwd.is_empty() && self.resolve(cwd) == Some(cwd) else { return None }
  Some(cwd)
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
  let annotated : Map[String, Json] = Map([])
  for key, field in thread {
    annotated[key] = field
  }
  if thread.get("cwd") is Some(String(cwd)) &&
    !cwd.trim().is_empty() &&
    self.resolve(cwd) is Some(project) {
    annotated["projectRoot"] = Json::string(project)
  }
  Json::object(annotated)
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
  let annotated : Map[String, Json] = Map([])
  for key, field in fields {
    annotated[key] = field
  }
  if fields.get("data") is Some(Array(threads)) {
    let data : Array[Json] = []
    for thread in threads {
      data.push(self.annotate_thread(thread))
    }
    annotated["data"] = Json::array(data)
  }
  if fields.get("thread") is Some(thread) {
    annotated["thread"] = self.annotate_thread(thread)
  }
  Json::object(annotated)
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
    Some(Some("/Users/me/src/openseek")),
  )
}

///|
async test "Codex draft projects accept only the main checkout" {
  let catalog = ProjectCatalog()
  catalog.roots["/workspace/project"] = Some("/workspace/project")
  catalog.roots["/worktrees/a/project"] = Some("/workspace/project")
  assert_eq(
    catalog.main_project("/workspace/project"),
    Some("/workspace/project"),
  )
  assert_true(catalog.main_project("/worktrees/a/project") is None)
}

///|
async test "Codex thread replies retain cwd and receive cached project roots" {
  let catalog = ProjectCatalog()
  catalog.roots["/worktrees/a/project"] = Some("/workspace/project")
  let annotated = catalog.annotate({
    "data": [
      { "id": "thread-a", "cwd": "/worktrees/a/project", "preview": "First" },
    ],
  })
  guard annotated is Object(fields) &&
    fields.get("data") is Some(Array([Object(thread)])) else {
    fail("expected annotated thread list")
  }
  assert_eq(thread.get("projectRoot"), Some(Json::string("/workspace/project")))
  assert_eq(thread.get("cwd"), Some(Json::string("/worktrees/a/project")))
}
