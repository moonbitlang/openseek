// Downloading and verifying a macOS update bundle. Staging is the paranoid
// half of self-update: nothing here touches the running bundle, and nothing
// gets handed to apply until the archive digest matched the manifest and
// the extracted bundle carries a valid signature from the same Developer ID
// team as the running app — a compromised download source can therefore
// nudge, but not install.

///|
/// A staging or apply failure, with a user-facing message.
pub(all) suberror UpdateError {
  /// A self-update failure with a human-readable diagnostic.
  UpdateError(String)
}

///|
pub impl Show for UpdateError with fn output(self, logger) {
  match self {
    UpdateError(message) => logger.write_string(message)
  }
}

///|
/// A verified update bundle waiting to be applied.
pub struct StagedUpdate {
  version : String
  app_path : String
}

///|
/// The staging directory under the app's per-user work directory. Wiped
/// before every download and by `cleanup_leftovers`.
fn staging_dir(work_dir : String) -> String {
  work_dir + "/update"
}

///|
/// Download `info`'s platform package into the staging directory, verify
/// its digest and code signature, and return the staged bundle. The running
/// bundle must be signed by a real team (an ad-hoc dev build never
/// self-updates), and the staged bundle must be signed by the same one.
pub async fn stage_update(
  info : UpdateInfo,
  work_dir~ : String,
  bundle_path~ : String,
) -> StagedUpdate {
  guard info.artifact is Some(artifact) else {
    raise UpdateError("the manifest carries no package for this platform")
  }
  guard team_identifier(bundle_path) is Some(team) else {
    raise UpdateError("the running bundle is not Developer ID signed")
  }
  let staging = staging_dir(work_dir)
  remove_tree(staging)
  @fs.mkdir(staging, recursive=true)
  let archive = staging + "/package.zip"
  download(artifact.url, archive)
  verify_digest(archive, artifact.sha256)
  let extract_dir = staging + "/extract"
  run_tool("ditto", ["-x", "-k", archive, extract_dir])
  let app_path = extracted_app(extract_dir)
  // The zip may carry quarantine attributes; the bundle is notarized, but
  // stripping them keeps the relaunch from stopping at a Gatekeeper prompt.
  // Best-effort: a failure only means the prompt shows once.
  ignore(@process.run("xattr", ["-dr", "com.apple.quarantine", app_path]))
  run_tool("codesign", ["--verify", "--deep", "--strict", app_path])
  guard team_identifier(app_path) is Some(new_team) && new_team == team else {
    raise UpdateError("the downloaded bundle is signed by a different team")
  }
  { version: info.version, app_path }
}

///|
async fn download(url : String, destination : String) -> Unit {
  let (response, data) = @http.get(url) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise UpdateError("update download failed: \{error}")
  }
  guard response.code == 200 else {
    raise UpdateError("update download returned HTTP \{response.code}")
  }
  @fs.write_file(destination, data, create_mode=CreateOrTruncate)
}

///|
async fn verify_digest(archive : String, expected : String) -> Unit {
  let bytes = @fs.read_file(archive).binary()
  let actual = @crypto.bytes_to_hex_string(@crypto.sha256(bytes)).to_lower()
  guard actual == expected else {
    raise UpdateError("update package digest mismatch")
  }
}

///|
/// The single .app entry the archive extracted to.
async fn extracted_app(extract_dir : String) -> String {
  for entry in @fs.readdir(extract_dir) {
    if entry.has_suffix(".app") {
      return extract_dir + "/" + entry
    }
  }
  raise UpdateError("the update package contains no .app bundle")
}

///|
/// Run a verification/extraction tool, failing loudly with its output.
async fn run_tool(command : String, args : Array[String]) -> Unit {
  let (code, output) = @process.collect_output_merged(
    command,
    args,
    inherit_env=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise UpdateError("\{command} failed: \{error}")
  }
  guard code == 0 else {
    raise UpdateError("\{command} failed: \{output.text().trim()}")
  }
}

///|
/// The bundle's signing team, from `codesign -dv`; None for unsigned or
/// ad-hoc ("not set") signatures.
async fn team_identifier(app_path : String) -> String? {
  let (code, output) = @process.collect_output_merged(
    "codesign",
    ["-dv", app_path],
    inherit_env=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard code == 0 else { return None }
  for line in output.text().split("\n") {
    if line.trim().strip_prefix("TeamIdentifier=") is Some(team) {
      let team = team.trim().to_owned()
      if team.is_empty() || team == "not set" {
        return None
      }
      return Some(team)
    }
  }
  None
}
