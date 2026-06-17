///|
const MoonbitVersionFile : String = ".moonbit-version"

///|
const MoonbitToolchainCacheDir : String = "dist/tools/moonbit"

///|
const MoonbitCliBaseUrl : String = "https://cli.moonbitlang.com"

///|
const MoonbitSeedVersionFile : String = ".openseek-moonbit-seed-version"

///|
/// Platform-specific descriptor for the MoonBit toolchain seed staged into a
/// desktop package.
struct MoonbitToolchainTarget {
  name : String
  archive_target : String
  archive_extension : String
  executable_suffix : String
  uses_zip : Bool
}

///|
/// Return the Windows x64 MoonBit toolchain target.
pub fn moonbit_windows_x64_toolchain() -> MoonbitToolchainTarget {
  {
    name: "windows-x64",
    archive_target: "windows-x86_64",
    archive_extension: "zip",
    executable_suffix: ".exe",
    uses_zip: true,
  }
}

///|
/// Return the Linux x64 MoonBit toolchain target.
pub fn moonbit_linux_x64_toolchain() -> MoonbitToolchainTarget {
  {
    name: "linux-x64",
    archive_target: "linux-x86_64",
    archive_extension: "tar.gz",
    executable_suffix: "",
    uses_zip: false,
  }
}

///|
/// Return the macOS arm64 MoonBit toolchain target.
pub fn moonbit_macos_arm64_toolchain() -> MoonbitToolchainTarget {
  {
    name: "macos-arm64",
    archive_target: "darwin-aarch64",
    archive_extension: "tar.gz",
    executable_suffix: "",
    uses_zip: false,
  }
}

///|
/// Return the package-relative seed directory for this MoonBit target.
pub fn MoonbitToolchainTarget::seed_relative_dir(
  self : MoonbitToolchainTarget,
) -> String {
  "toolchains/moonbit/" + self.name
}

///|
fn MoonbitToolchainTarget::binary_archive_name(
  self : MoonbitToolchainTarget,
) -> String {
  "moonbit-" + self.archive_target + "." + self.archive_extension
}

///|
fn MoonbitToolchainTarget::binary_cache_path(
  self : MoonbitToolchainTarget,
  version : String,
) -> String {
  MoonbitToolchainCacheDir +
  "/moonbit-" +
  self.archive_target +
  "-" +
  version +
  "." +
  self.archive_extension
}

///|
fn MoonbitToolchainTarget::core_cache_path(
  self : MoonbitToolchainTarget,
  version : String,
) -> String {
  let extension = if self.uses_zip { "zip" } else { "tar.gz" }
  MoonbitToolchainCacheDir + "/core-" + version + "." + extension
}

///|
fn MoonbitToolchainTarget::binary_url(
  self : MoonbitToolchainTarget,
  version : String,
) -> String {
  MoonbitCliBaseUrl +
  "/binaries/" +
  moonbit_url_version(version) +
  "/" +
  self.binary_archive_name()
}

///|
fn MoonbitToolchainTarget::core_url(
  self : MoonbitToolchainTarget,
  version : String,
) -> String {
  let extension = if self.uses_zip { "zip" } else { "tar.gz" }
  MoonbitCliBaseUrl +
  "/cores/core-" +
  moonbit_url_version(version) +
  "." +
  extension
}

///|
fn MoonbitToolchainTarget::compiler_command(
  self : MoonbitToolchainTarget,
  payload_dir : String,
) -> String {
  payload_dir + "/bin/moonc" + self.executable_suffix
}

///|
fn moonbit_url_version(version : String) -> String {
  version.replace(old="+", new="%2B")
}

///|
async fn read_moonbit_version(ws : @packaging.Workspace) -> String {
  let version = @asyncfs.read_file(ws.at(MoonbitVersionFile))
    .text()
    .trim()
    .to_owned()
  if version.is_empty() {
    raise @packaging.PackageError("\{ws.at(MoonbitVersionFile)} is empty")
  }
  if version.has_prefix("v") {
    raise @packaging.PackageError(
      "\{ws.at(MoonbitVersionFile)} should not start with 'v'",
    )
  }
  version
}

///|
async fn download_file_if_missing(url : String, path : String) -> Unit {
  if @asyncfs.exists(path) {
    return
  }
  println("downloading \{url}")
  let (response, body) = @http.get(url)
  if response.code < 200 || response.code >= 300 {
    raise @packaging.PackageError(
      "failed to download \{url}: HTTP \{response.code} \{response.reason}",
    )
  }
  @asyncfs.write_file(path, body, create_mode=CreateOrTruncate)
}

///|
async fn extract_zip_archive(
  ws : @packaging.Workspace,
  archive : String,
  destination : String,
) -> Unit {
  @packaging.run_checked(
    "powershell",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      "$ErrorActionPreference = 'Stop'; " +
      "$archive = '\{archive}'; " +
      "$destination = '\{destination}'; " +
      "Expand-Archive $archive -DestinationPath $destination -Force",
    ],
    dir=ws.dir(),
  )
}

///|
async fn extract_tar_gz_archive(
  ws : @packaging.Workspace,
  archive : String,
  destination : String,
) -> Unit {
  @packaging.run_checked(
    "tar",
    ["-xzf", archive, "-C", destination],
    dir=ws.dir(),
  )
}

///|
async fn extract_archive(
  ws : @packaging.Workspace,
  archive : String,
  destination : String,
  uses_zip~ : Bool,
) -> Unit {
  if uses_zip {
    extract_zip_archive(ws, archive, destination)
  } else {
    extract_tar_gz_archive(ws, archive, destination)
  }
}

///|
async fn chmod_executable_files(
  ws : @packaging.Workspace,
  dir : String,
) -> Unit {
  if !@asyncfs.exists(ws.at(dir)) {
    return
  }
  for entry in @asyncfs.readdir(ws.at(dir), sort=true) {
    let path = dir + "/" + entry
    if @asyncfs.kind(ws.at(path)) is Directory {
      chmod_executable_files(ws, path)
    } else {
      @packaging.run_checked("chmod", ["+x", path], dir=ws.dir())
    }
  }
}

///|
async fn normalize_seed_executable_bits(
  ws : @packaging.Workspace,
  target : MoonbitToolchainTarget,
  payload_dir : String,
) -> Unit {
  if target.executable_suffix != "" {
    return
  }
  chmod_executable_files(ws, payload_dir + "/bin")
}

///|
async fn compiler_version(
  target : MoonbitToolchainTarget,
  payload : String,
) -> String {
  let compiler = target.compiler_command(payload)
  let (code, output) = @process.collect_output_merged(
    compiler,
    ["-v"],
    inherit_env=true,
  )
  if code != 0 {
    raise @packaging.PackageError(
      "failed to read MoonBit compiler version from \{compiler}: \{output.text().trim()}",
    )
  }
  let version = output.text().trim().split(" ").collect()[0].to_owned()
  if version.has_prefix("v") {
    version[1:].to_owned()
  } else {
    version
  }
}

///|
/// Download and stage a platform-specific MoonBit toolchain seed into a
/// package directory. The seed is intentionally not bundled in place; runtime
/// initialization copies it to the per-user writable runtime directory first.
pub async fn stage_moonbit_toolchain_seed(
  ws : @packaging.Workspace,
  target : MoonbitToolchainTarget,
  payload_dir : String,
) -> Unit {
  let version = read_moonbit_version(ws)
  let binary_archive = target.binary_cache_path(version)
  let core_archive = target.core_cache_path(version)
  @packaging.ensure_dir(ws.at(MoonbitToolchainCacheDir))
  download_file_if_missing(target.binary_url(version), ws.at(binary_archive))
  download_file_if_missing(target.core_url(version), ws.at(core_archive))
  @packaging.remove_path_if_exists(ws.at(payload_dir))
  @packaging.ensure_dir(ws.at(payload_dir))
  extract_archive(ws, binary_archive, payload_dir, uses_zip=target.uses_zip)
  @packaging.ensure_dir(ws.at(payload_dir + "/lib"))
  extract_archive(
    ws,
    core_archive,
    payload_dir + "/lib",
    uses_zip=target.uses_zip,
  )
  @packaging.remove_path_if_exists(ws.at(payload_dir + "/lib/core/_build"))
  normalize_seed_executable_bits(ws, target, payload_dir)
  let actual_version = compiler_version(target, ws.at(payload_dir))
  if actual_version != version {
    raise @packaging.PackageError(
      "downloaded MoonBit version \{actual_version}, expected \{version}",
    )
  }
  @packaging.write_text(
    ws.at(payload_dir + "/" + MoonbitSeedVersionFile),
    version,
  )
}
