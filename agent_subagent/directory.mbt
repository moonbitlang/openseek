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
/// `path` resolved as a worker's directory: canonical, strictly below the
/// launching checkout, and what its sandbox denies — the checkout, and the
/// git metadata of the repository the directory is in when that lies
/// outside it (the directory's own `.git` the profile always pins).
async fn Launcher::resolve_directory(
  self : Launcher,
  path : String,
) -> Result[(String, Array[String]), String] {
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
  Ok((directory, deny_roots))
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
/// denies: the worker enforces with what it is handed.
fn directory_input(
  input : Map[String, Json],
  directory : String,
  deny_roots : Array[String],
) -> Json {
  let fields = Map::from_iter(input.iter())
  fields["mode"] = "directory"
  fields["worker_root"] = Json(directory)
  fields["deny_roots"] = Json(deny_roots)
  Json::object(fields)
}
