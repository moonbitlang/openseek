///|
#cfg(target="native")
let native_distribution : Bool = true

///|
#cfg(not(target="native"))
let native_distribution : Bool = false

///|
fn is_windows() -> Bool {
  @async.platform is Windows
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
async fn copy_tree(source : String, destination : String) -> Unit {
  if @fs.kind(source) is Directory {
    @fs.mkdir(destination, recursive=true, allow_exist=true)
    for name in @fs.readdir(source, include_hidden=true) {
      copy_tree(source + "/" + name, destination + "/" + name)
    }
  } else {
    copy_file(source, destination)
  }
}

///|
async fn install(
  home : String,
  source_cli : String,
  available~ : async (String, Array[String]) -> Bool,
  toolchain~ : async (String) -> Unit,
) -> Unit {
  let source_cli = @fs.realpath(source_cli)
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
  // Validate the extracted distribution before changing the user's toolchain.
  if !@fs.exists(source + "/bin/" + rg_name) {
    fail(
      "Extract the complete OpenSeek archive before running setup: missing rg",
    )
  }
  // The installed CLI can run setup too: preserve its source before removal.
  let stage = @fs.tmpdir(prefix="openseek-share-")
  defer @fs.rmdir(stage, recursive=true)
  copy_tree(source + "/share", stage + "/share")
  let needs_moonbit = !moonbit_available(home, available)
  if needs_moonbit {
    toolchain(home + "/.moon")
  }
  copy_file(source + "/bin/" + rg_name, bin + "/" + rg_name, executable=true)
  @fs.rmdir(root + "/share", recursive=true) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => ()
    error => raise error
  }
  copy_tree(stage + "/share", root + "/share")
  if needs_cli {
    copy_file(source_cli, bin + "/" + cli_name, executable=true)
  }
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
  install(home, @exe.current_exe(), available=usable, toolchain=install_moonbit)
  @stdio.stdout.write(
    "Installation complete. Add \{home}/.moon/bin and \{home}/.openseek/bin to PATH.\n",
  )
}
