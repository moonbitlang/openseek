///|
const MermaidVersion : String = "11.16.0"

///|
const MermaidArchiveSha256 : String = "ff48c94a0a0458b377a5187ad01407184d2a182e6476c2015b7068ff58355fae"

///|
const MermaidArchiveName : String = "mermaid-\{MermaidVersion}.tgz"

///|
const MermaidArchiveUrl : String = "https://registry.npmjs.org/mermaid/-/\{MermaidArchiveName}"

///|
const MermaidEntry : String = "mermaid.esm.min.mjs"

///|
const MermaidChunks : String = "chunks/mermaid.esm.min"

///|
/// Errors raised while staging the pinned Mermaid browser distribution.
pub(all) suberror MermaidAssetError {
  /// The pinned Mermaid browser distribution could not be staged.
  MermaidAssetError(String)
}

///|
pub impl Show for MermaidAssetError with fn output(self, logger) {
  match self {
    MermaidAssetError(message) =>
      logger.write_string("Mermaid asset error: \{message}")
  }
}

///|
async fn ensure_dir(path : String) -> Unit {
  if !@asyncfs.exists(path) {
    @asyncfs.mkdir(path, recursive=true)
  }
}

///|
async fn remove_path_if_exists(path : String) -> Unit {
  if !@asyncfs.exists(path) {
    return
  }
  if @asyncfs.kind(path) is Directory {
    @asyncfs.rmdir(path, recursive=true)
  } else {
    @asyncfs.remove(path)
  }
}

///|
async fn archive_digest(path : String) -> String {
  let bytes = @asyncfs.read_file(path).binary()
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes)).to_lower()
}

///|
async fn ensure_cached_archive(cache_dir : String) -> String {
  ensure_dir(cache_dir)
  let path = cache_dir + "/" + MermaidArchiveName
  if @asyncfs.exists(path) {
    let actual = archive_digest(path)
    if actual == MermaidArchiveSha256 {
      return path
    }
    println(
      "cached \{MermaidArchiveName} failed SHA-256 verification; downloading it again",
    )
    remove_path_if_exists(path)
  }
  println("downloading \{MermaidArchiveUrl}")
  let (response, body) = @http.get(MermaidArchiveUrl) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise MermaidAssetError(
        "failed to download \{MermaidArchiveUrl}: \{error}",
      )
  }
  if response.code < 200 || response.code >= 300 {
    raise MermaidAssetError(
      "failed to download \{MermaidArchiveUrl}: HTTP \{response.code} \{response.reason}",
    )
  }
  @asyncfs.write_file(path, body, create_mode=CreateOrTruncate)
  let actual = archive_digest(path)
  if actual != MermaidArchiveSha256 {
    remove_path_if_exists(path)
    raise MermaidAssetError(
      "SHA-256 mismatch for \{MermaidArchiveName}: expected \{MermaidArchiveSha256}, got \{actual}",
    )
  }
  path
}

///|
async fn run_tar(
  archive : String,
  destination : String,
  working_dir : String,
  extra_args : Array[String],
) -> Unit {
  let command_args = ["-xzf", archive, "-C", destination]
  for arg in extra_args {
    command_args.push(arg)
  }
  println("$ [\{working_dir}] tar \{command_args.join(" ")}")
  let code = @process.run(
    "tar",
    command_args,
    inherit_env=true,
    cwd=working_dir.view(),
  ) catch {
    error =>
      raise MermaidAssetError(
        "failed to launch tar while extracting \{MermaidArchiveName}: \{error}",
      )
  }
  if code != 0 {
    raise MermaidAssetError(
      "tar failed with exit code \{code} while extracting \{MermaidArchiveName}",
    )
  }
}

///|
/// Download the pinned official Mermaid npm archive, verify it, and recreate
/// the destination with only the minified ESM entry, its relative chunks, and
/// the upstream license. The verified archive remains reusable by later
/// offline builds.
pub async fn stage(
  cache_dir : String,
  destination : String,
  working_dir : String,
) -> Unit {
  let archive = ensure_cached_archive(cache_dir)
  remove_path_if_exists(destination)
  ensure_dir(destination)
  run_tar(archive, destination, working_dir, [
    "--strip-components=2",
    "--exclude=*.map",
    "package/dist/" + MermaidEntry,
    "package/dist/" + MermaidChunks,
  ])
  run_tar(archive, destination, working_dir, [
    "--strip-components=1", "package/LICENSE",
  ])
  let entry = destination + "/" + MermaidEntry
  let chunks = destination + "/" + MermaidChunks
  let license = destination + "/LICENSE"
  if !@asyncfs.exists(entry) ||
    !@asyncfs.exists(chunks) ||
    !@asyncfs.exists(license) {
    remove_path_if_exists(destination)
    raise MermaidAssetError(
      "extracted \{MermaidArchiveName} is missing its ESM entry, chunks, or LICENSE",
    )
  }
}

///|
pub extend MermaidAssetError with Show::{output, to_string}
