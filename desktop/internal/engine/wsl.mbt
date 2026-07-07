// Where a run's serve engine lives: natively on this machine, or inside a
// WSL distro on Windows. WSL mode gives the agent a Linux toolchain and
// filesystem while the desktop host (and the session store it manages)
// stays on the Windows side. The host spawns `wsl.exe` as the engine
// process; stdin/stdout JSONL passes through the relay unchanged, so the
// serve protocol needs no awareness of it.

///|
#cfg(platform="windows")
const WslSupported : Bool = true

///|
#cfg(not(platform="windows"))
const WslSupported : Bool = false

///|
/// `wsl.exe` resolves through PATH (System32), so the host never needs to
/// know where Windows keeps it.
const WslProgram : String = "wsl.exe"

///|
/// The fallback engine command when the payload names none and the bundle
/// carries no Linux engine: `openseek` on the distro's PATH.
const DefaultWslEngine : String = "openseek"

///|
/// The bundled Linux engine, staged by the Windows packaging script beside
/// the Windows engine binary. It only exists when the packaging machine had
/// a WSL toolchain to build it with.
const BundledWslEngineName : String = "openseek-linux"

///|
/// Where a run's engine process is hosted. `Wsl` names the distro (`None` =
/// the user's default distro) and the engine command inside it.
priv enum EngineHost {
  Native
  Wsl(distro~ : String?, engine~ : String)
}

///|
/// The validated engine host of a start payload: `Native` unless the
/// payload opts into WSL, which is refused outright on platforms without
/// WSL so the failure is a clear message instead of a cryptic spawn error.
/// `native_engine` is the bundled Windows engine; an unnamed WSL engine
/// resolves to the Linux engine staged beside it when the bundle has one.
async fn engine_host(wsl : WslRequest?, native_engine : String) -> EngineHost {
  guard wsl is Some(wsl) else { return Native }
  guard WslSupported else {
    raise EngineError("WSL engine mode is only available on Windows")
  }
  let engine = match wsl.engine {
    Some(engine) => engine
    None => default_wsl_engine(native_engine)
  }
  Wsl(distro=wsl.distro, engine~)
}

///|
/// The engine command for a WSL run that names none: the bundled Linux
/// engine when the bundle has one (addressed through its `/mnt/...` mount,
/// since a Windows path means nothing to the distro's shell), otherwise
/// `openseek` on the distro's PATH — the pre-bundling behavior, and the one
/// source checkouts get.
async fn default_wsl_engine(native_engine : String) -> String {
  guard sibling_path(native_engine, BundledWslEngineName) is Some(bundled) else {
    return DefaultWslEngine
  }
  guard windows_path_to_wsl_mount(bundled) is Some(mounted) else {
    return DefaultWslEngine
  }
  let exists = @fs.exists(bundled) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if exists {
    mounted
  } else {
    DefaultWslEngine
  }
}

///|
/// The path of `name` in the same directory as `path`, or `None` when
/// `path` has no directory component to derive it from.
fn sibling_path(path : String, name : String) -> String? {
  // Scan by UTF-16 offset so the slice below cuts at the separator itself,
  // independent of any non-ASCII characters earlier in the path.
  let mut split = -1
  for index in 0..<path.length() {
    if path[index] is ('\\' | '/') {
      split = index
    }
  }
  if split < 0 {
    None
  } else {
    Some(path[:split + 1].to_owned() + name)
  }
}

///|
/// A Windows drive path as the distro sees it under the default automount
/// (`C:\foo\bar` → `/mnt/c/foo/bar`); `None` for anything else (UNC paths,
/// relative paths). A non-default automount root makes this mapping wrong —
/// those setups name the engine explicitly in the settings instead.
fn windows_path_to_wsl_mount(path : String) -> String? {
  guard path.get_char(0) is Some(drive) &&
    drive is ('a'..='z' | 'A'..='Z') &&
    path.get_char(1) is Some(':') &&
    path.get_char(2) is Some('\\' | '/') else {
    return None
  }
  let mounted = StringBuilder::new()
  mounted.write_string("/mnt/")
  mounted.write_char(drive.to_ascii_lowercase())
  for c in path[2:] {
    if c is '\\' {
      mounted.write_char('/')
    } else {
      mounted.write_char(c)
    }
  }
  Some(mounted.to_string())
}

///|
/// The program and argument list that serve one conversation. Native runs
/// the bundled engine directly. WSL selects the distro, enters the working
/// directory, and runs the engine inside it: `--cd` is resolved by wsl.exe
/// itself and accepts both Windows paths (translated to their `/mnt/...`
/// mount) and absolute Linux paths, so the host never translates paths.
///
/// The engine path is passed raw, as its own argument. wsl.exe routes the
/// post-`--` tokens through the distro's shell but quotes each one itself,
/// so a path with spaces survives as a single word — pre-quoting it here
/// would make the quote characters part of the filename the shell looks up.
fn EngineHost::serve_command(
  self : EngineHost,
  native_engine : String,
  cwd : @path.Path?,
) -> (String, Array[String]) {
  match self {
    Native => (native_engine, ["serve", "--dir", "."])
    Wsl(distro~, engine~) => {
      let args : Array[String] = []
      if distro is Some(distro) {
        args.push("-d")
        args.push(distro)
      }
      if cwd is Some(cwd) {
        args.push("--cd")
        args.push(cwd.to_string())
      }
      args.push("--")
      args.push(engine)
      args.push("serve")
      args.push("--dir")
      args.push(".")
      (WslProgram, args)
    }
  }
}

///|
/// The fingerprint fragment that pins a serve process to its engine host —
/// switching between native and WSL (or between distros) must replace the
/// process.
fn EngineHost::fingerprint(self : EngineHost) -> String {
  match self {
    Native => "native"
    Wsl(distro~, engine~) => "wsl\u{0}\{distro.unwrap_or("")}\u{0}\{engine}"
  }
}

///|
/// Variables the WSL engine needs from the host, declared for wsl.exe's
/// Win32→WSL environment sharing. `/u` shares the value as-is only in that
/// direction; host-side paths add `/p` so wsl.exe rewrites the Windows path
/// to its `/mnt/...` mount. The WSL engine then reads the same session store
/// and global skills library that the desktop host manages.
const WslEnvPassthrough : String = "DEEPSEEK/u:OPENSEEK_MODEL/u:OPENSEEK_MAX_STEPS/u:OPENSEEK_DIR/u:OPENSEEK_API_URL/u:OPENSEEK_SESSION/u:OPENSEEK_SESSION_ROOT/up:OPENSEEK_GLOBAL_SKILLS_DIR/up"

///|
/// The WSLENV value for an engine spawn: the user's own sharing list (WSLENV
/// is a shared resource — clobbering it would silently break their setup)
/// extended with the engine's variables.
fn wslenv_with_passthrough(existing : String?) -> String {
  match existing {
    Some(value) if !value.trim().is_empty() => value + ":" + WslEnvPassthrough
    _ => WslEnvPassthrough
  }
}

///|
test "serve command selects distro and cwd, passing the engine path raw" {
  let full : EngineHost = Wsl(
    distro=Some("Ubuntu"),
    engine="/mnt/c/Program Files/OpenSeek/openseek-linux",
  )
  let (program, args) = full.serve_command(
    "C:\\bundle\\openseek.exe",
    Some("C:\\Users\\me\\.openseek\\workspaces\\s1"),
  )
  assert_eq(program, "wsl.exe")
  json_inspect(args, content=[
    "-d", "Ubuntu", "--cd", "C:\\Users\\me\\.openseek\\workspaces\\s1", "--", "/mnt/c/Program Files/OpenSeek/openseek-linux",
    "serve", "--dir", ".",
  ])
  let minimal : EngineHost = Wsl(distro=None, engine=DefaultWslEngine)
  let (program, args) = minimal.serve_command("C:\\bundle\\openseek.exe", None)
  assert_eq(program, "wsl.exe")
  json_inspect(args, content=["--", "openseek", "serve", "--dir", "."])
  let native : EngineHost = Native
  let (program, args) = native.serve_command("C:\\bundle\\openseek.exe", None)
  assert_eq(program, "C:\\bundle\\openseek.exe")
  json_inspect(args, content=["serve", "--dir", "."])
}

///|
test "engine host fingerprints distinguish native, distro, and engine" {
  let hosts : Array[EngineHost] = [
    Native,
    Wsl(distro=None, engine="openseek"),
    Wsl(distro=Some("Ubuntu"), engine="openseek"),
    Wsl(distro=Some("Ubuntu"), engine="/usr/local/bin/openseek"),
  ]
  let prints = hosts.map(host => host.fingerprint())
  for i, a in prints {
    for j, b in prints {
      if i != j {
        assert_true(a != b)
      }
    }
  }
}

///|
test "wslenv extends the user's own sharing list" {
  assert_true(WslEnvPassthrough.contains("OPENSEEK_GLOBAL_SKILLS_DIR/up"))
  assert_eq(wslenv_with_passthrough(None), WslEnvPassthrough)
  assert_eq(wslenv_with_passthrough(Some("  ")), WslEnvPassthrough)
  assert_eq(
    wslenv_with_passthrough(Some("MYVAR/u")),
    "MYVAR/u:" + WslEnvPassthrough,
  )
}

///|
test "windows drive paths map to their default automount" {
  assert_true(
    windows_path_to_wsl_mount("C:\\Program Files\\OpenSeek\\openseek-linux")
    is Some("/mnt/c/Program Files/OpenSeek/openseek-linux"),
  )
  assert_true(
    windows_path_to_wsl_mount("d:/tools/openseek-linux")
    is Some("/mnt/d/tools/openseek-linux"),
  )
  assert_true(windows_path_to_wsl_mount("\\\\server\\share\\engine") is None)
  assert_true(windows_path_to_wsl_mount("relative\\engine") is None)
  assert_true(windows_path_to_wsl_mount("") is None)
}

///|
test "sibling path replaces the file name component" {
  assert_true(
    sibling_path("C:\\bundle\\openseek.exe", "openseek-linux")
    is Some("C:\\bundle\\openseek-linux"),
  )
  assert_true(
    sibling_path("C:/bundle/openseek.exe", "openseek-linux")
    is Some("C:/bundle/openseek-linux"),
  )
  assert_true(sibling_path("openseek.exe", "openseek-linux") is None)
}
