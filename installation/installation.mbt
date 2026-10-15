///|
#cfg(target="native")
let native_distribution : Bool = true

///|
#cfg(not(target="native"))
let native_distribution : Bool = false

///|
fn is_windows() -> Bool {
  @env.get_env_var("OS") == Some("Windows_NT")
}

///|
fn executable_name(name : String) -> String {
  if is_windows() {
    name + ".exe"
  } else {
    name
  }
}

///|
async fn copy_file(
  source : String,
  destination : String,
  executable~ : Bool = false,
) -> Unit {
  @fs.write_file(destination, @fs.read_file(source))
  if executable && !is_windows() {
    @fs.chmod(destination, 0o755)
  }
}

///|
async fn command(
  program : String,
  args : Array[String],
  extra_env~ : Map[String, String] = {},
) -> String {
  let (stdin, writer) = @process.write_to_process()
  writer.close()
  let (code, output, errors) = @process.collect_output(
    program,
    args,
    stdin~,
    extra_env~,
    no_console_window=true,
  )
  guard code == 0 else { fail("\{program} exited \{code}: \{errors.text()}") }
  output.text()
}

///|
async fn usable(program : String, args : Array[String]) -> Bool {
  try {
    ignore(command(program, args))
    true
  } catch {
    _ => false
  }
}

///|
async fn moonbit_available(
  home : String,
  available : async (String, Array[String]) -> Bool,
) -> Bool {
  // The official installer extracts the binaries before downloading core.
  // Version commands alone must not mark an interrupted SDK as usable.
  if available(home + "/.moon/bin/" + executable_name("moon"), ["version"]) {
    let core = @fs.kind(home + "/.moon/lib/core") catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => return false
      error => raise error
    }
    if core != Directory {
      return false
    }
  }
  for
    (name, args) in [
      ("moon", ["version"]),
      ("moonc", ["-v"]),
      ("moonrun", ["--version"]),
      ("moonx", ["--version"]),
    ] {
    if !available(home + "/.moon/bin/" + executable_name(name), args) &&
      !available(name, args) {
      return false
    }
  }
  true
}

///|
fn resource_files() -> Array[String] {
  [
    "doc/moonbit/index.md", "doc/moonbit/language/index.md", "doc/moonbit/toolchain/index.md",
    "workflow/read.mbtx",
  ]
}

///|
async fn resources_available(directory : String) -> Bool {
  for file in resource_files() {
    let kind = @fs.kind(directory + "/" + file) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => return false
      error => raise error
    }
    if kind != Regular {
      return false
    }
  }
  true
}

///|
/// Fill missing resource files without replacing the user's existing copies.
async fn copy_missing(source : String, destination : String) -> Unit {
  if @fs.kind(source) is Directory {
    @fs.mkdir(destination, recursive=true, allow_exist=true)
    for name in @fs.readdir(source, include_hidden=true) {
      copy_missing(source + "/" + name, destination + "/" + name)
    }
  } else if !@fs.exists(destination) {
    copy_file(source, destination)
  } else if @fs.kind(destination) != Regular {
    fail("resource path is not a file: \{destination}")
  }
}

///|
async fn install(
  home : String,
  source_cli : String,
  available~ : async (String, Array[String]) -> Bool,
  toolchain~ : async (String) -> Unit,
) -> Bool {
  let source = @path.Path(source_cli).dirname().dirname().to_string()
  let root = home + "/.openseek"
  let bin = root + "/bin"
  @fs.mkdir(bin, recursive=true, allow_exist=true)
  let lock = @fs.open(
    root + "/setup.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  @async.with_timeout(1200000, () => lock.lock(Exclusive))
  let cli_name = executable_name("openseek")
  let rg_name = executable_name("rg")
  let needs_cli = !available(bin + "/" + cli_name, ["--help"])
  let needs_rg = !available(bin + "/" + rg_name, ["--version"]) &&
    !available("rg", ["--version"])
  let needs_resources = !resources_available(root + "/share")
  // Validate the extracted distribution before changing the user's toolchain.
  if needs_rg && !available(source + "/bin/" + rg_name, ["--version"]) {
    fail(
      "Extract the complete OpenSeek archive before running setup: missing rg",
    )
  }
  if needs_resources && !resources_available(source + "/share") {
    fail(
      "Extract the complete OpenSeek archive before running setup: missing share",
    )
  }
  let needs_moonbit = !moonbit_available(home, available)
  if needs_moonbit {
    toolchain(home + "/.moon")
    guard moonbit_available(home, available) else {
      fail("MoonBit installation is not usable")
    }
  }
  if needs_rg {
    copy_file(source + "/bin/" + rg_name, bin + "/" + rg_name, executable=true)
  }
  if needs_resources {
    copy_missing(source + "/share", root + "/share")
  }
  if needs_cli {
    copy_file(source_cli, bin + "/" + cli_name, executable=true)
  }
  !(needs_moonbit || needs_cli || needs_rg || needs_resources)
}

///|
fn curl_args(url : String) -> Array[String] {
  [
    "--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir",
    "=https", "--connect-timeout", "15", "--max-time", "600", "--retry", "2", url,
  ]
}

///|
async fn download_file(url : String, destination : String) -> Unit {
  ignore(command("curl", [..curl_args(url), "--output", destination]))
}

///|
async fn install_moonbit(destination : String) -> Unit {
  let stage = @fs.tmpdir(prefix="moonbit-install-")
  defer @fs.rmdir(stage, recursive=true)
  let windows = is_windows()
  let script = stage + (if windows { "/install.ps1" } else { "/install.sh" })
  download_file(
    "https://cli.moonbitlang.com/install/" +
    (if windows { "powershell.ps1" } else { "unix.sh" }),
    script,
  )
  let destination = if windows {
    destination.replace_all(old="/", new="\\")
  } else {
    destination
  }
  let extra_env = {
    "HOME": stage,
    "USERPROFILE": stage,
    "MOON_HOME": destination,
    "MOONBIT_INSTALL_DEV": "",
    "MOONBIT_INSTALL_VERSION": "",
    "PATH": destination +
    (if windows { "\\bin;" } else { "/bin:" }) +
    @env.get_env_var("PATH").unwrap_or(""),
  }
  @async.with_timeout(900000, () => {
    ignore(
      command(
        if windows {
          "powershell.exe"
        } else {
          "bash"
        },
        if windows {
          ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script]
        } else {
          [script]
        },
        extra_env~,
      ),
    )
  })
}

///|
/// Install the extracted native distribution and any missing MoonBit tools.
pub async fn setup() -> Unit {
  guard native_distribution else {
    fail("setup requires the native OpenSeek binary distribution")
  }
  let home = if is_windows() {
    @env.get_env_var("USERPROFILE")
  } else {
    @env.get_env_var("HOME")
  }
  guard home is Some(home) && @path.Path(home).is_absolute() else {
    fail("HOME (USERPROFILE on Windows) must name an absolute directory")
  }
  let reused = install(
    home,
    @exe.current_exe(),
    available=usable,
    toolchain=install_moonbit,
  )
  @stdio.stdout.write(
    (if reused {
      "Dependencies are ready. "
    } else {
      "Installation complete. "
    }) +
    "Add \{home}/.moon/bin and \{home}/.openseek/bin to PATH.\n",
  )
}
