///|
const FrontendPackage : String = "frontend"

///|
/// The JS bundle `moon build frontend --target js --release` emits.
const FrontendBundleArtifact : String = "_build/js/release/build/openseek_desktop/frontend/frontend.js"

///|
/// The stable path the host and packagers read the frontend bundle from.
const FrontendBundleOutput : String = "frontend.js"

///|
const NativePackage : String = "."

///|
const NativeBinary : String = "_build/native/release/build/openseek_desktop/openseek_desktop.exe"

///|
const EnginePackage : String = "cmd/openseek"

///|
const EngineBinary : String = "_build/native/release/build/bobzhang/openseek/cmd/openseek/openseek.exe"

///|
/// Raised when a packaging helper cannot complete a filesystem, build, or
/// toolchain step.
pub(all) suberror PackageError {
  /// A packaging failure with a human-readable diagnostic.
  PackageError(String)
}

///|
/// The desktop workspace being packaged. The value is opaque to callers so
/// all path decisions stay centralized here.
struct Workspace {
  dir : String
}

///|
/// Locate the desktop workspace from either the workspace directory itself or
/// the monorepo root.
pub async fn locate_workspace() -> Workspace {
  for candidate in [".", "desktop"] {
    if @asyncfs.exists(candidate + "/moon.mod") &&
      @asyncfs.exists(candidate + "/lepus") &&
      @asyncfs.exists(candidate + "/frontend") {
      return { dir: candidate }
    }
  }
  raise PackageError(
    "cannot locate the desktop workspace; run from the desktop directory or the monorepo root",
  )
}

///|
/// Return the desktop workspace directory.
pub fn Workspace::dir(self : Workspace) -> String {
  self.dir
}

///|
/// Resolve a path relative to the desktop workspace directory.
pub fn Workspace::at(self : Workspace, relative : String) -> String {
  self.dir + "/" + relative
}

///|
/// The monorepo root, one level up from the desktop workspace.
pub fn Workspace::repo(self : Workspace) -> String {
  self.dir + "/.."
}

///|
/// Resolve a path relative to the monorepo root.
pub fn Workspace::repo_at(self : Workspace, relative : String) -> String {
  self.repo() + "/" + relative
}

///|
/// Return the release-mode native desktop host binary path under the desktop
/// workspace.
pub fn Workspace::native_binary(self : Workspace) -> String {
  self.at(NativeBinary)
}

///|
/// Return the release-mode openseek engine binary path under the monorepo
/// root.
pub fn Workspace::engine_binary(self : Workspace) -> String {
  self.repo_at(EngineBinary)
}

///|
/// Return the openseek engine package path relative to the monorepo root.
pub fn engine_package() -> String {
  EnginePackage
}

///|
/// Return the POSIX lepus code generation tool path relative to the desktop
/// workspace.
pub fn posix_codegen_tool() -> String {
  "lepus/target/lepus-tools/lepus_cli"
}

///|
/// Return the Windows lepus code generation tool path relative to the desktop
/// workspace.
pub fn windows_codegen_tool() -> String {
  "lepus/target/lepus-tools/lepus_cli.exe"
}

///|
/// Resolve a path to an absolute path using the host filesystem rules.
pub fn absolute_path(path : String) -> String {
  (path : @path.Path).resolve().to_string()
}

///|
/// Run a subprocess in `dir`, inherit the current environment, and raise
/// `PackageError` when the command exits with a non-zero status.
pub async fn run_checked(
  command : String,
  args : Array[String],
  dir~ : String,
  extra_env? : Map[String, String] = {},
) -> Unit {
  let joined_args = args.join(" ")
  println("$ [\{dir}] \{command} \{joined_args}")
  let code = @process.run(
    command,
    args,
    inherit_env=true,
    extra_env~,
    cwd=dir.view(),
  )
  if code != 0 {
    raise PackageError("command failed with exit code \{code}: \{command}")
  }
}

///|
/// Install the lepus code generation tool if the requested workspace-relative
/// tool path does not already exist.
pub async fn ensure_codegen_tool(ws : Workspace, tool_path : String) -> Unit {
  if @asyncfs.exists(ws.at(tool_path)) {
    return
  }
  run_checked(
    "moon",
    ["install", "./cli", "--bin", "target/lepus-tools"],
    dir=ws.at("lepus"),
  )
}

///|
/// Build the frontend package and copy the generated JS bundle to the stable
/// `frontend.js` path the host and packagers consume.
pub async fn build_frontend_bundle(ws : Workspace) -> Unit {
  run_checked(
    "moon",
    ["build", FrontendPackage, "--target", "js", "--release"],
    dir=ws.dir(),
  )
  copy_file(ws.at(FrontendBundleArtifact), ws.at(FrontendBundleOutput))
}

///|
/// Build the native desktop host in release mode.
pub async fn build_native_host(
  ws : Workspace,
  extra_args? : Array[String] = [],
  extra_env? : Map[String, String] = {},
) -> Unit {
  run_checked(
    "moon",
    ["build", NativePackage, "--target", "native", "--release"] + extra_args,
    dir=ws.dir(),
    extra_env~,
  )
}

///|
/// Build the openseek engine from the monorepo source so the bundled engine
/// always matches the checkout instead of whatever happens to be on PATH.
pub async fn build_engine(
  ws : Workspace,
  extra_env? : Map[String, String] = {},
) -> Unit {
  run_checked(
    "moon",
    ["build", EnginePackage, "--target", "native", "--release"],
    dir=ws.repo(),
    extra_env~,
  )
  let engine_binary = ws.engine_binary()
  if !@asyncfs.exists(engine_binary) {
    raise PackageError("openseek engine binary not found: \{engine_binary}")
  }
}

///|
/// Copy a file, replacing the destination if it already exists.
pub async fn copy_file(source : String, destination : String) -> Unit {
  @asyncfs.write_file(
    destination,
    @asyncfs.read_file(source),
    create_mode=CreateOrTruncate,
  )
}

///|
/// Write UTF-8 text to a file, replacing the file if it already exists.
pub async fn write_text(path : String, content : String) -> Unit {
  @asyncfs.write_file(path, content, create_mode=CreateOrTruncate)
}

///|
/// Create a directory and any missing parents if the path does not exist.
pub async fn ensure_dir(path : String) -> Unit {
  if !@asyncfs.exists(path) {
    @asyncfs.mkdir(path, recursive=true)
  }
}

///|
/// Remove a file or directory tree if it already exists.
pub async fn remove_path_if_exists(path : String) -> Unit {
  if !@asyncfs.exists(path) {
    return
  }
  if @asyncfs.kind(path) is Directory {
    @asyncfs.rmdir(path, recursive=true)
  } else {
    @asyncfs.remove(path)
  }
}
