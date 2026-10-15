///|
priv struct Release {
  id : String
  platform : String
  url : String
  sha256 : String
  moonbit_version : String
}

///|
fn decode_release(source : String) -> Release raise {
  guard @json.parse(source)
    is {
      "id": String(id),
      "platform": String(platform),
      "url": String(url),
      "sha256": String(sha256),
      "moonbit_version": String(moonbit_version),
      ..
    } &&
    !id.is_empty() &&
    (platform == "linux-x64" || platform == "linux-arm64") &&
    url.has_prefix("https://") &&
    sha256.length() == 64 &&
    sha256.iter().all(c => c is ('0'..<='9' | 'a'..<='f')) &&
    !moonbit_version.is_empty() else {
    fail("invalid embedded CLI release manifest")
  }
  { id, platform, url, sha256, moonbit_version, }
}

///|
fn release() -> Release? raise {
  release_manifest().map(decode_release)
}

///|
fn data_home() -> String raise {
  let base = match @env.get_env_var("XDG_DATA_HOME") {
    Some(value) if !value.is_empty() => value
    _ =>
      match @env.get_env_var("HOME") {
        Some(home) if !home.is_empty() => home + "/.local/share"
        _ => fail("HOME or XDG_DATA_HOME must name an absolute directory")
      }
  }
  guard base.has_prefix("/") else {
    fail("HOME or XDG_DATA_HOME must name an absolute directory")
  }
  base + "/openseek/runtimes"
}

///|
async fn optional_text(path : String) -> String? {
  Some(@fs.read_file(path).text()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    error => raise error
  }
}

///|
fn required_files() -> Array[String] {
  [
    "toolchain/bin/moon", "toolchain/bin/moonc", "toolchain/bin/moonrun", "toolchain/bin/moonx",
    "bin/rg", "share/doc/moonbit/index.md",
  ]
}

///|
async fn check_layout(root : String) -> Unit {
  for path in required_files() {
    guard @fs.kind(root + "/" + path) is Regular else {
      fail("incomplete CLI runtime: \{path}")
    }
  }
  for path in ["share/workflow", "toolchain/lib/core"] {
    guard @fs.kind(root + "/" + path) is Directory else {
      fail("incomplete CLI runtime: \{path}")
    }
  }
}

///|
/// The immutable runtime selected by this binary, not by the current directory
/// or an ambient MoonBit installation. None means setup has not completed.
pub async fn runtime_directory() -> String? {
  guard release() is Some(info) else { return None }
  let root = data_home() + "/" + info.sha256
  guard optional_text(root + "/.complete") is Some(stamp) else { return None }
  guard stamp == info.sha256 else {
    fail("CLI runtime completion stamp differs")
  }
  check_layout(root)
  Some(root)
}

///|
/// Apply only to this CLI process and its children. Registry identity and
/// caches in MOON_HOME, the user's shell files, and global PATH stay intact.
pub async fn configure() -> Unit {
  guard release() is Some(_) else { return }
  guard runtime_directory() is Some(root) else {
    fail("CLI runtime is not installed; run openseek setup")
  }
  @env.set_env_var(
    "PATH",
    root +
    "/toolchain/bin:" +
    root +
    "/bin:" +
    @env.get_env_var("PATH").unwrap_or("/usr/bin:/bin"),
  )
}

///|
async fn command(program : String, args : Array[String]) -> String {
  let (stdin, writer) = @process.write_to_process()
  writer.close()
  let (code, output, errors) = @process.collect_output(
    program,
    args,
    stdin~,
    no_console_window=true,
  )
  guard code == 0 else { fail("\{program} exited \{code}: \{errors.text()}") }
  output.text()
}

///|
async fn checksum(path : String) -> String {
  let input = @fs.open(path, mode=ReadOnly)
  defer input.close()
  let hash = @crypto.SHA256::new()
  while input.read_some(max_len=65536) is Some(bytes) {
    hash.update(bytes)
  }
  @crypto.bytes_to_hex_string(hash.finalize())
}

///|
async fn probe(root : String, info : Release) -> Unit {
  check_layout(root)
  let version = command(root + "/toolchain/bin/moonc", ["-v"])
  guard version.contains(info.moonbit_version) else {
    fail("installed MoonBit version differs from the CLI release")
  }
  ignore(command(root + "/toolchain/bin/moon", ["version"]))
  ignore(command(root + "/toolchain/bin/moonrun", ["--version"]))
  ignore(command(root + "/bin/rg", ["--version"]))
}

///|
async fn install(
  info : Release,
  base : String,
  progress : async (String) -> Unit,
  download~ : async (String, String) -> Unit,
  toolchain~ : async (String, String) -> Unit,
) -> (String, Bool) {
  @fs.mkdir(base, recursive=true, allow_exist=true, permission=0o700)
  let lock = @fs.open(
    base + "/setup.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  progress("waiting_for_lock")
  @async.with_timeout(1200000, () => lock.lock(Exclusive))
  let root = base + "/" + info.sha256
  if optional_text(root + "/.complete") is Some(stamp) {
    guard stamp == info.sha256 else {
      fail("CLI runtime completion stamp differs")
    }
    progress("verify_installed")
    probe(root, info)
    return (root, true)
  }
  // A unique sibling keeps incomplete downloads out of the selected runtime;
  // rename publishes only a fully checked installation on the same filesystem.
  guard @env.rand(16) is Some(random) else {
    fail("could not create setup directory name")
  }
  let stage = base + "/.setup-" + @crypto.bytes_to_hex_string(random)
  @fs.mkdir(stage, permission=0o700)
  defer @fs.rmdir(stage, recursive=true)
  let archive = stage + "/runtime.tar.gz"
  let payload = stage + "/payload"
  @fs.mkdir(payload)
  progress("download")
  download(info.url, archive)
  progress("verify_download")
  guard checksum(archive) == info.sha256 else {
    fail("CLI runtime download checksum mismatch")
  }
  progress("extract")
  ignore(command("tar", ["-xzf", archive, "-C", payload]))
  progress("install_moonbit")
  toolchain(payload + "/toolchain", info.moonbit_version)
  progress("verify_runtime")
  probe(payload, info)
  @fs.write_file(
    payload + "/.complete",
    info.sha256,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(payload, root)
  (root, false)
}

///|
async fn download_archive(url : String, destination : String) -> Unit {
  ignore(
    command("curl", [
      "--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir",
      "=https", "--connect-timeout", "15", "--max-time", "600", "--retry", "2", "--output",
      destination, url,
    ]),
  )
}

///|
async fn install_moonbit(destination : String, version : String) -> Unit {
  let home = destination + "-installer-home"
  @fs.mkdir(home)
  defer @fs.rmdir(home, recursive=true)
  let script = home + "/install.sh"
  download_archive("https://cli.moonbitlang.com/install/unix.sh", script)
  // Scope the official installer's temporary downloads and profile handling to
  // its own home. The user's SDK, shell files, and registry remain untouched.
  @async.with_timeout(900000, () => {
    ignore(
      command("env", [
        "HOME=" + home,
        "MOON_HOME=" + destination,
        "MOONBIT_INSTALL_DEV=",
        "PATH=" +
        destination +
        "/bin:" +
        @env.get_env_var("PATH").unwrap_or("/usr/bin:/bin"),
        "bash",
        script,
        version,
      ]),
    )
  })
}

///|
/// Download this CLI release's runtime. Git and Codex remain user-managed.
pub async fn setup(json~ : Bool, runtime_url? : String) -> Unit {
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
    guard release() is Some(info) else {
      fail(
        "this development build has no release runtime; use a published native CLI",
      )
    }
    let info = match runtime_url {
      None => info
      Some(url) => {
        guard url.has_prefix("https://") else {
          fail("--runtime-url requires HTTPS")
        }
        { ..info, url, }
      }
    }
    event("check_platform")
    let platform = command("uname", ["-sm"]).trim().to_owned()
    let expected = if info.platform == "linux-x64" {
      "Linux x86_64"
    } else {
      "Linux aarch64"
    }
    guard platform == expected else {
      fail("CLI runtime requires \{expected}; found \{platform}")
    }
    let (root, reused) = install(
      info,
      data_home(),
      event,
      download=download_archive,
      toolchain=install_moonbit,
    )
    Ok((info, root, reused))
  } catch {
    error => Err(error)
  }
  match result {
    Ok((info, root, reused)) =>
      if json {
        @stdio.stdout.write(
          (
            {
              "event": "ready",
              "release": info.id,
              "platform": info.platform,
              "runtime_dir": root,
              "reused": reused,
            } : Json).stringify() +
          "\n",
        )
      } else {
        @stdio.stdout.write("OpenSeek is ready: \{root}\n")
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
