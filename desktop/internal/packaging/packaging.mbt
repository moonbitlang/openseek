///|
const FrontendPackage : String = "frontend"

///|
const NativePackage : String = "."

///|
const NativeBinary : String = "_build/native/release/build/openseek_desktop/openseek_desktop.exe"

///|
const EnginePackage : String = "cmd/openseek"

///|
const EngineBinary : String = "_build/native/release/build/bobzhang/openseek/cmd/openseek/openseek.exe"

///|
pub(all) suberror PackageError {
  PackageError(String)
}

///|
/// The desktop workspace being packaged. The value is opaque to callers so
/// all path decisions stay centralized here.
struct Workspace {
  dir : String
}

///|
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
pub fn Workspace::dir(self : Workspace) -> String {
  self.dir
}

///|
pub fn Workspace::at(self : Workspace, relative : String) -> String {
  self.dir + "/" + relative
}

///|
/// The monorepo root, one level up from the desktop workspace.
pub fn Workspace::repo(self : Workspace) -> String {
  self.dir + "/.."
}

///|
pub fn Workspace::repo_at(self : Workspace, relative : String) -> String {
  self.repo() + "/" + relative
}

///|
pub fn native_binary() -> String {
  NativeBinary
}

///|
pub fn engine_binary() -> String {
  EngineBinary
}

///|
pub fn engine_package() -> String {
  EnginePackage
}

///|
pub fn posix_codegen_tool() -> String {
  "lepus/target/lepus-tools/lepus_cli"
}

///|
pub fn windows_codegen_tool() -> String {
  "lepus/target/lepus-tools/lepus_cli.exe"
}

///|
pub fn absolute_path(path : String) -> String {
  (path : @path.Path).resolve().to_string()
}

///|
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
pub async fn build_frontend_bundle(
  ws : Workspace,
  helper_target_dir? : String,
) -> Unit {
  run_checked(
    "moon",
    ["build", FrontendPackage, "--target", "js", "--release"],
    dir=ws.dir(),
  )
  let helper_args = match helper_target_dir {
    Some(target_dir) => ["--target-dir", target_dir]
    None => []
  }
  run_checked(
    "moon",
    helper_args + ["run", "--target", "native", "build_frontend.mbtx"],
    dir=ws.dir(),
  )
}

///|
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
  if !@asyncfs.exists(ws.repo_at(EngineBinary)) {
    raise PackageError(
      "openseek engine binary not found: \{ws.repo_at(EngineBinary)}",
    )
  }
}

///|
pub async fn copy_file(source : String, destination : String) -> Unit {
  @asyncfs.write_file(
    destination,
    @asyncfs.read_file(source),
    create_mode=CreateOrTruncate,
  )
}

///|
pub async fn write_text(path : String, content : String) -> Unit {
  @asyncfs.write_file(path, content, create_mode=CreateOrTruncate)
}

///|
pub async fn ensure_dir(path : String) -> Unit {
  if !@asyncfs.exists(path) {
    @asyncfs.mkdir(path, recursive=true)
  }
}

///|
pub async fn remove_path_if_exists(path : String) -> Unit {
  if !@asyncfs.exists(path) {
    return
  }
  match @asyncfs.kind(path) {
    Directory => @asyncfs.rmdir(path, recursive=true)
    _ => @asyncfs.remove(path)
  }
}
