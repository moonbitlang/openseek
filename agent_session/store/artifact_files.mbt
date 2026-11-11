///|
/// Prospective output path inside the session's existing scratch directory.
/// Writers create the directory when publishing files.
pub async fn SessionStore::artifact_dir(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String {
  self.scratch_dir(id) + "/artifact"
}

///|
async fn validate_artifact_directory(
  scratch : String,
  directory : String,
) -> Unit {
  guard @fs.kind(scratch, follow_symlink=false) is Directory &&
    @fs.kind(directory, follow_symlink=false) is Directory else {
    fail("artifact directory must stay inside this conversation's scratch")
  }
}

///|
async fn copy_artifact_tree(source : String, destination : String) -> Unit {
  for name in @fs.readdir(source, include_hidden=true) {
    let from = "\{source}/\{name}"
    let to = "\{destination}/\{name}"
    match @fs.kind(from, follow_symlink=false) {
      Directory => {
        @fs.mkdir(to)
        copy_artifact_tree(from, to)
      }
      Regular =>
        @fs.write_binary(to, @fs.read_binary(from), create_mode=CreateNew)
      _ =>
        fail(
          "cannot fork an artifact bundle containing a symlink or special file",
        )
    }
  }
}
