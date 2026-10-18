///|
/// Where a worker works: in a worktree forked for it (`Worktree`), or in
/// place, in a directory below the launching checkout that it has to itself
/// while it runs (`Directory`, relative to the checkout). Separate
/// repositories in one directory, or a module each, need nothing forked:
/// they cannot collide.
pub(all) enum Workplace {
  Worktree(Slice)
  Directory(String)
}

///|
/// A worker's directory as its launcher resolved it: canonical; what its
/// sandbox denies (the checkout, and the git metadata of the repository the
/// directory is in when that lies outside it — the directory's own `.git`
/// the profile always pins); and that repository's index file, the one piece
/// of git state it may write, so `git restore` works.
priv struct ResolvedDirectory {
  directory : String
  deny_roots : Array[String]
  git_index : String?
}

///|
/// `path` resolved as a worker's directory, strictly below the launching
/// checkout.
async fn Launcher::resolve_directory(
  self : Launcher,
  path : String,
) -> Result[ResolvedDirectory, String] {
  guard self.cwd is Some(cwd) else {
    return Err("this session has no checkout to work in")
  }
  let root = @fs.realpath(cwd) catch {
    error => return Err("the session's checkout does not resolve: \{error}")
  }
  let requested = if @path.Path(path).is_absolute() {
    path
  } else {
    "\{root}/\{path}"
  }
  let directory = @fs.realpath(requested) catch {
    _ => return Err("\{path} does not exist")
  }
  guard (@fs.kind(directory) catch { _ => Regular }) is Directory else {
    return Err("\{path} is not a directory")
  }
  guard @workspace_path.is_under_workspace_root(root, directory) &&
    directory != root else {
    return Err(
      "\{path} must be a directory below the session's checkout \{root}",
    )
  }
  let relative = directory.view(start_offset=root.length() + 1).to_owned()
  guard !relative.split("/").any(part => part is (".git" | ".worktrees")) else {
    return Err(
      "\{path} is git metadata or a worktree, not a directory to work in",
    )
  }
  // `moon` builds a module at its root: a worker in a directory inside one
  // could neither build nor test it.
  let mut above = @workspace_path.parent_dir(directory)
  while above is Some(dir) && @workspace_path.is_under_workspace_root(root, dir) {
    for manifest in ["moon.mod", "moon.mod.json", "moon.work"] {
      if (@fs.exists("\{dir}/\{manifest}") catch { _ => false }) {
        return Err(
          "\{path} is inside the MoonBit module or workspace at \{dir}, which builds at its root; give a worker that root, or a worktree",
        )
      }
    }
    above = if dir == root { None } else { @workspace_path.parent_dir(dir) }
  }
  let deny_roots = [root]
  let common = @subtask.git_require(
    ["rev-parse", "--path-format=absolute", "--git-common-dir"],
    cwd=directory,
  )
  let common = match common {
    Ok(common) => Some(@fs.realpath(common.trim())) catch { _ => None }
    Err(_) => None
  }
  if common is Some(common) &&
    !@workspace_path.is_under_workspace_root(root, common) {
    deny_roots.push(common)
  }
  // Canonical like every profile path: its directory is realpath'd, since
  // the file itself may not exist yet.
  let index = @subtask.git_require(
    ["rev-parse", "--path-format=absolute", "--git-path", "index"],
    cwd=directory,
  )
  let git_index = match index {
    Ok(index) => {
      let index = index.trim().to_owned()
      match @workspace_path.parent_dir(index) {
        Some(parent) =>
          Some(
            @workspace_path.join_child(
              @fs.realpath(parent),
              @workspace_path.path_basename(index),
            ),
          ) catch {
            _ => None
          }
        None => None
      }
    }
    Err(_) => None
  }
  Ok({ directory, deny_roots, git_index, })
}

///|
/// Hold `directory` for the worker `session`, unless a running worker's
/// directory is it, holds it, or lies inside it. Does not suspend, so two
/// starts cannot both take one directory.
fn Launcher::reserve_directory(
  self : Launcher,
  session : String,
  directory : String,
) -> Result[Unit, String] {
  for other, held in self.directories {
    if @workspace_path.is_under_workspace_root(held, directory) ||
      @workspace_path.is_under_workspace_root(directory, held) {
      return Err(
        "\{directory} overlaps \{held}, where worker \{other} is running; wait for it to end",
      )
    }
  }
  self.directories[session] = directory
  Ok(())
}

///|
/// `input` with the directory a worker was given and what its sandbox
/// denies and allows: the worker enforces with what it is handed, so none of
/// it is the caller's to set.
fn directory_input(
  input : Map[String, Json],
  resolved : ResolvedDirectory,
) -> Json {
  let fields = Map::from_iter(input.iter())
  fields["mode"] = "directory"
  fields["worker_root"] = Json(resolved.directory)
  fields["deny_roots"] = Json(resolved.deny_roots)
  fields.remove("git_index")
  if resolved.git_index is Some(index) {
    fields["git_index"] = Json(index)
  }
  Json::object(fields)
}
