// The app launcher: detect which of a curated set of editors/terminals are
// installed, hand the frontend their names and icons, and open one of them on
// the active conversation's working directory. macOS only for now — the
// catalog, the install probe, the icon extraction, and the launch command are
// all platform-specific; other platforms report an empty catalog, so the
// frontend hides the launcher.

///|
/// A detected app, kept in the module cache so `launch_app` can resolve an id
/// back to the `.app` it found. `app_path` is empty for `reveal_only` entries
/// (Finder), which open the directory through the platform default instead.
priv struct LauncherApp {
  id : String
  name : String
  // A `data:image/png` URL, or empty when the icon could not be extracted.
  icon : String
  app_path : String
  reveal_only : Bool
}

///|
/// One catalog entry to probe for: the stable id reported to the frontend, the
/// display name, the `.app` basenames to look for (without `.app`), a bundle id
/// for the Spotlight fallback, and whether launching just reveals the folder.
priv struct AppCandidate {
  id : String
  name : String
  app_names : Array[String]
  bundle_id : String
  reveal_only : Bool
}

///|
/// The detected catalog, built once on first use and reused for the app run.
/// Two concurrent builds would just race to the same result, so no lock.
let app_catalog_cache : Ref[Array[LauncherApp]?] = Ref(None)

///|
async fn ensure_app_catalog() -> Array[LauncherApp] {
  if app_catalog_cache.val is Some(apps) {
    return apps
  }
  let apps = build_app_catalog()
  app_catalog_cache.val = Some(apps)
  apps
}

///|
async fn list_apps_op() -> ListAppsReply {
  let apps = ensure_app_catalog()
  { apps: apps.map(app => { id: app.id, name: app.name, icon: app.icon }) }
}

///|
async fn launch_app_op(payload : LaunchAppPayload) -> LaunchAppReply {
  // A live run hands us its cwd; a resumed conversation has none, so fall back
  // to the directory the session's engine runs in (same as `open_path`).
  let dir = if payload.cwd.is_empty() {
    @engine.session_cwd(payload.session)
  } else {
    payload.cwd
  }
  guard !dir.is_empty() else {
    raise HostError("This conversation has no working directory yet")
  }
  let apps = ensure_app_catalog()
  let mut target : LauncherApp? = None
  for app in apps {
    if app.id == payload.app {
      target = Some(app)
      break
    }
  }
  guard target is Some(app) else {
    raise HostError("Unknown app \"\{payload.app}\"")
  }
  // The engine creates a conversation's workspace on its first run, so a chat
  // that has never run has no directory to open. The frontend disables the
  // launcher in that case; this is the backstop if one slips through.
  guard (@fs.exists(dir) catch { _ => true }) else {
    raise HostError(
      "This chat has no workspace yet — send a message to start it",
    )
  }
  run_app_open(app, dir)
  { launched: true }
}

///|
/// The curated macOS catalog, in the order the menu lists them.
fn mac_candidates() -> Array[AppCandidate] {
  [
    {
      id: "vscode",
      name: "VS Code",
      app_names: ["Visual Studio Code"],
      bundle_id: "com.microsoft.VSCode",
      reveal_only: false,
    },
    {
      id: "cursor",
      name: "Cursor",
      app_names: ["Cursor"],
      bundle_id: "",
      reveal_only: false,
    },
    {
      id: "emacs",
      name: "Emacs",
      app_names: ["Emacs"],
      bundle_id: "",
      reveal_only: false,
    },
    {
      id: "zed",
      name: "Zed",
      app_names: ["Zed"],
      bundle_id: "dev.zed.Zed",
      reveal_only: false,
    },
    {
      id: "finder",
      name: "Finder",
      app_names: ["Finder"],
      bundle_id: "com.apple.finder",
      reveal_only: true,
    },
    {
      id: "terminal",
      name: "Terminal",
      app_names: ["Terminal"],
      bundle_id: "com.apple.Terminal",
      reveal_only: false,
    },
    {
      id: "iterm2",
      name: "iTerm2",
      app_names: ["iTerm"],
      bundle_id: "com.googlecode.iterm2",
      reveal_only: false,
    },
    {
      id: "ghostty",
      name: "Ghostty",
      app_names: ["Ghostty"],
      bundle_id: "com.mitchellh.ghostty",
      reveal_only: false,
    },
    {
      id: "xcode",
      name: "Xcode",
      app_names: ["Xcode"],
      bundle_id: "com.apple.dt.Xcode",
      reveal_only: false,
    },
    {
      id: "androidstudio",
      name: "Android Studio",
      app_names: ["Android Studio"],
      bundle_id: "",
      reveal_only: false,
    },
  ]
}

///|
#cfg(platform="windows")
async fn build_app_catalog() -> Array[LauncherApp] {
  []
}

///|
/// macOS (and Linux, where the probe simply finds nothing). On Linux the
/// catalog is empty, so the launcher button stays hidden.
#cfg(not(platform="windows"))
async fn build_app_catalog() -> Array[LauncherApp] {
  guard uname_is_darwin() else { return [] }
  let result : Array[LauncherApp] = []
  for candidate in mac_candidates() {
    guard locate_app(candidate) is Some(app_path) else { continue }
    let icon = app_icon_data_url(candidate.id, app_path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ""
    }
    result.push({
      id: candidate.id,
      name: candidate.name,
      icon,
      app_path,
      reveal_only: candidate.reveal_only,
    })
  }
  result
}

///|
/// The standard locations an app bundle can live in.
#cfg(not(platform="windows"))
fn app_search_dirs() -> Array[String] {
  let dirs = [
    "/Applications", "/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices",
  ]
  if @home.dir() is Some(home) {
    dirs.push(home.to_string() + "/Applications")
  }
  dirs
}

///|
/// Find an installed app: scan the standard bundle locations for one of its
/// `.app` basenames, then fall back to a Spotlight lookup by bundle id (catches
/// nonstandard install locations).
#cfg(not(platform="windows"))
async fn locate_app(candidate : AppCandidate) -> String? {
  for dir in app_search_dirs() {
    for name in candidate.app_names {
      let path = "\{dir}/\{name}.app"
      if (@fs.exists(path) catch { _ => false }) {
        return Some(path)
      }
    }
  }
  if !candidate.bundle_id.is_empty() {
    if mdfind_bundle(candidate.bundle_id) is Some(path) {
      return Some(path)
    }
  }
  None
}

///|
/// Resolve an app bundle's path from its bundle id via Spotlight.
#cfg(not(platform="windows"))
async fn mdfind_bundle(bundle_id : String) -> String? {
  let (code, stdout, _) = @process.collect_output("mdfind", [
    "kMDItemCFBundleIdentifier == '\{bundle_id}'",
  ]) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard code == 0 else { return None }
  let text = stdout.text() catch { _ => return None }
  for line in text.split("\n") {
    let path = line.trim().to_owned()
    if path.has_suffix(".app") && (@fs.exists(path) catch { _ => false }) {
      return Some(path)
    }
  }
  None
}

///|
/// Extract an app's icon as a `data:image/png` URL: locate its `.icns`, resize
/// it to a PNG with `sips`, and base64-encode the result. Returns empty on any
/// failure — the frontend falls back to a letter avatar.
#cfg(not(platform="windows"))
async fn app_icon_data_url(id : String, app_path : String) -> String {
  guard find_app_icns(app_path) is Some(icns) else { return "" }
  guard icon_cache_dir() is Some(cache_dir) else { return "" }
  @fs.mkdir(cache_dir, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  let png = "\{cache_dir}/\{id}.png"
  let code = @process.run("sips", [
    "-s", "format", "png", "-Z", "64", icns, "--out", png,
  ])
  guard code == 0 else { return "" }
  let bytes = @fs.read_file(png).binary()
  "data:image/png;base64,\{@base64.encode(bytes)}"
}

///|
#cfg(not(platform="windows"))
fn icon_cache_dir() -> String? {
  if @home.dir() is Some(home) {
    Some(home.to_string() + "/Library/Caches/OpenSeek/app-icons")
  } else {
    None
  }
}

///|
/// Find an app's `.icns`: prefer the `CFBundleIconFile` named in Info.plist,
/// then any `.icns` in Resources (apps that ship their icon in an asset catalog
/// have neither and return `None`).
#cfg(not(platform="windows"))
async fn find_app_icns(app_path : String) -> String? {
  let resources = "\{app_path}/Contents/Resources"
  let named = read_icon_name("\{app_path}/Contents/Info")
  if !named.is_empty() {
    let file = if named.has_suffix(".icns") { named } else { named + ".icns" }
    let path = "\{resources}/\{file}"
    if (@fs.exists(path) catch { _ => false }) {
      return Some(path)
    }
  }
  let entries = @fs.readdir(resources) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  let mut fallback : String? = None
  for entry in entries {
    if entry.has_suffix(".icns") {
      if entry == "AppIcon.icns" {
        return Some("\{resources}/\{entry}")
      }
      if fallback is None {
        fallback = Some("\{resources}/\{entry}")
      }
    }
  }
  fallback
}

///|
/// Read `CFBundleIconFile` from an app's Info.plist (handles binary plists,
/// which `defaults` decodes); empty when the key is absent.
#cfg(not(platform="windows"))
async fn read_icon_name(info_path : String) -> String {
  let (code, stdout, _) = @process.collect_output("defaults", [
    "read", info_path, "CFBundleIconFile",
  ]) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return ""
  }
  guard code == 0 else { return "" }
  (stdout.text() catch { _ => "" }).trim().to_owned()
}

///|
/// Launch a detected app on `dir`, raising a `HostError` carrying the reason
/// `open` reported (its stderr) when it fails. `reveal_only` apps (Finder) take
/// the directory through the platform default; everything else opens it with the
/// resolved bundle.
#cfg(not(platform="windows"))
async fn run_app_open(app : LauncherApp, dir : String) -> Unit {
  let args = if app.reveal_only { [dir] } else { ["-a", app.app_path, dir] }
  let (code, _, stderr) = @process.collect_output("open", args) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("Could not open \{app.name} (\{dir}): \{error}")
  }
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    let reason = if detail.is_empty() {
      "open exited with code \{code}"
    } else {
      detail
    }
    raise HostError("Could not open \{app.name} (\{dir}): \{reason}")
  }
}

///|
#cfg(platform="windows")
async fn run_app_open(app : LauncherApp, dir : String) -> Unit {
  let _ = app
  raise HostError("The app launcher is not supported on Windows: \{dir}")
}
