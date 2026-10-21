///|
test "default remote bootstrap selects this build's CLI release" {
  let command = remote_command()
  assert_true(
    command.contains(
      "https://cli.moonbitlang.com/openseek/cli/releases/v" + CliRelease,
    ),
  )
}

///|
async fn preparation_fixture(
  home : String,
  fail_setup~ : Bool = false,
) -> String {
  let release = home + "/release"
  let distribution = release + "/openseek-macos-arm64"
  @fs.mkdir(distribution + "/bin", recursive=true)
  @fs.write_file(
    distribution + "/bin/openseek",
    "#!/bin/sh\nset -eu\ncase \"$1\" in\nsetup) printf 'setup\\n' >> \"$HOME/actions\"; " +
    (if fail_setup { "exit 19" } else { "true" }) +
    ";;\n*) exit 1;;\nesac\n",
    permission=0o755,
  )
  @fs.write_file(
    distribution + "/bin/openseek-app-server",
    "#!/bin/sh\nset -eu\n[ \"$#\" -eq 0 ]\nprintf 'server\\n' >> \"$HOME/actions\"\nprintf '{\"port\":1234}\\n'\n",
    permission=0o755,
  )
  // uname is the only platform shim; curl, tar and the generated bootstrap are real.
  @fs.mkdir(home + "/tools")
  @fs.write_file(
    home + "/tools/uname",
    "#!/bin/sh\ncase \"$1\" in -s) echo Darwin;; -m) echo arm64;; esac\n",
    permission=0o755,
  )
  let (code, _, _) = @processx.collect_output_no_stdin("sh", [
    "-c",
    "cd " +
    shell_quote(release) +
    " && tar -czf openseek-macos-arm64.tar.gz openseek-macos-arm64 && " +
    "if command -v sha256sum >/dev/null 2>&1; then sha256sum openseek-macos-arm64.tar.gz; else shasum -a 256 openseek-macos-arm64.tar.gz; fi > SHA256SUMS",
  ])
  assert_eq(code, 0)
  release
}

///|
async fn run_preparation(
  home : String,
  release : String,
) -> (Int32, String, String) {
  let (code, out, err) = @processx.collect_output_no_stdin(
    "sh",
    ["-c", prepare_command("file://" + release, "=file")],
    extra_env={
      "HOME": home,
      "PATH": home +
      "/tools:" +
      @env.get_env_var("PATH").unwrap_or("/usr/bin:/bin"),
    },
  )
  (code, out.text(), err.text())
}

///|
async test "remote preparation downloads verifies installs and reuses the cached distribution" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="ssh-prepare-")
  defer @fs.rmdir(home, recursive=true)
  let release = preparation_fixture(home)
  let (code, out, err) = run_preparation(home, release)
  assert_eq(code, 0, msg=err)
  assert_true(
    out.contains("downloading") &&
    out.contains("installing") &&
    out.contains("\"port\":1234"),
  )
  assert_eq(@fs.read_file(home + "/actions").text(), "setup\nserver\n")
  assert_true(@fs.exists(home + "/.openseek/ssh/v" + CliRelease + "/.prepared"))
  @fs.rmdir(release, recursive=true)
  let (again, output, error) = run_preparation(home, release)
  assert_eq(again, 0, msg=error)
  assert_false(output.contains("downloading") || output.contains("installing"))
  assert_eq(@fs.read_file(home + "/actions").text(), "setup\nserver\nserver\n")
}

///|
async test "archive checksum failure never executes setup and a fresh download can retry" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="ssh-prepare-checksum-")
  defer @fs.rmdir(home, recursive=true)
  let release = preparation_fixture(home)
  let sums = @fs.read_file(release + "/SHA256SUMS")
  @fs.write_file(
    release + "/SHA256SUMS",
    "invalid  openseek-macos-arm64.tar.gz\n",
  )
  let (code, _, err) = run_preparation(home, release)
  assert_true(code != 0 && err.contains("checksum mismatch"))
  assert_false(@fs.exists(home + "/actions"))
  assert_eq(@fs.readdir(home + "/.openseek/ssh", include_hidden=true), [])
  @fs.write_file(release + "/SHA256SUMS", sums)
  let (retry, _, error) = run_preparation(home, release)
  assert_eq(retry, 0, msg=error)
}

///|
async test "failed setup is reported without starting or caching an app-server" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="ssh-prepare-install-")
  defer @fs.rmdir(home, recursive=true)
  let release = preparation_fixture(home, fail_setup=true)
  let (code, output, _) = run_preparation(home, release)
  assert_eq(code, 19)
  assert_true(output.contains("installing"))
  assert_eq(@fs.read_file(home + "/actions").text(), "setup\n")
  assert_eq(@fs.readdir(home + "/.openseek/ssh", include_hidden=true), [])
}
