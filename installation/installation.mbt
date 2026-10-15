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
  progress : async (String) -> Unit,
  available~ : async (String, Array[String]) -> Bool,
  bundle~ : async (String) -> Unit,
  toolchain~ : async (String) -> Unit,
  cli~ : async (String) -> Unit,
) -> Bool {
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
  progress("check_dependencies")
  let needs_moonbit = !moonbit_available(home, available)
  let cli_name = executable_name("openseek")
  let rg_name = executable_name("rg")
  let needs_cli = !available(bin + "/" + cli_name, ["--help"])
  let needs_rg = !available(bin + "/" + rg_name, ["--version"]) &&
    !available("rg", ["--version"])
  let needs_resources = !resources_available(root + "/share")
  if needs_moonbit {
    progress("install_moonbit")
    toolchain(home + "/.moon")
    guard moonbit_available(home, available) else {
      fail("MoonBit installation is not usable")
    }
  }
  let copy_cli = needs_cli && available(source_cli, ["--help"])
  if needs_rg || needs_resources {
    let stage = @fs.tmpdir(prefix="openseek-setup-")
    defer @fs.rmdir(stage, recursive=true)
    progress("download")
    bundle(stage)
    if needs_rg {
      guard available(stage + "/bin/" + rg_name, ["--version"]) else {
        fail("downloaded rg is not usable")
      }
    }
    if needs_resources {
      guard resources_available(stage + "/share") else {
        fail("downloaded resources are incomplete")
      }
    }
    if needs_rg {
      copy_file(stage + "/bin/" + rg_name, bin + "/" + rg_name, executable=true)
    }
    if needs_resources {
      copy_missing(stage + "/share", root + "/share")
    }
    copy_missing(stage + "/licenses", root + "/share/licenses")
  }
  if copy_cli {
    copy_file(source_cli, bin + "/" + cli_name, executable=true)
  } else if needs_cli {
    let stage = @fs.tmpdir(prefix="openseek-cli-")
    defer @fs.rmdir(stage, recursive=true)
    let path = stage + "/" + cli_name
    progress("download_cli")
    cli(path)
    guard available(path, ["--help"]) else {
      fail("downloaded openseek is not usable")
    }
    copy_file(path, bin + "/" + cli_name, executable=true)
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
/// Install missing dependencies; reuse working tools without changing other commands.
pub async fn setup(json~ : Bool, bundle_url? : String) -> Unit {
  async fn event(stage : String) -> Unit {
    if json {
      @stdio.stdout.write(
        ({ "event": "progress", "stage": stage } : Json).stringify() + "\n",
      )
    } else {
      @stdio.stderr.write("openseek setup: \{stage}\n")
    }
  }
  let result = try {
    let home = if is_windows() {
      @env.get_env_var("USERPROFILE")
    } else {
      @env.get_env_var("HOME")
    }
    guard home is Some(home) && @path.Path(home).is_absolute() else {
      fail("HOME (USERPROFILE on Windows) must name an absolute directory")
    }
    let manifest : Ref[Json?] = Ref(None)
    let reused = install(
      home,
      @exe.current_exe(),
      event,
      available=usable,
      bundle=destination => download_bundle(destination, bundle_url, manifest),
      toolchain=install_moonbit,
      cli=destination => download_cli(destination, bundle_url, manifest),
    )
    Ok((home, reused))
  } catch {
    error => Err(error)
  }
  match result {
    Ok((home, reused)) =>
      if json {
        @stdio.stdout.write(
          (
            {
              "event": "ready",
              "bin_dir": home + "/.openseek/bin",
              "share_dir": home + "/.openseek/share",
              "reused": reused,
            } : Json).stringify() +
          "\n",
        )
      } else {
        @stdio.stdout.write(
          "Dependencies are ready. Add \{home}/.moon/bin and \{home}/.openseek/bin to PATH.\n",
        )
      }
    Err(error) => {
      if json {
        @stdio.stdout.write(
          ({ "event": "error", "message": "\{error}" } : Json).stringify() +
          "\n",
        )
      }
      raise error
    }
  }
}
