///|
async fn fixture(root : String) -> (Release, String) {
  let payload = root + "/payload"
  for directory in ["bin", "share/doc/moonbit", "share/workflow"] {
    @fs.mkdir(payload + "/" + directory, recursive=true, allow_exist=true)
  }
  for file in required_files() {
    if file.has_prefix("toolchain/") {
      continue
    }
    let executable = file == "bin/rg"
    @fs.write_file(
      payload + "/" + file,
      if executable {
        "#!/bin/sh\nprintf 'fixture-sdk\\n'\n"
      } else {
        "resource"
      },
      permission=if executable { 0o755 } else { 0o644 },
    )
  }
  let archive = root + "/fixture.tar.gz"
  ignore(command("tar", ["-czf", archive, "-C", payload, "."]))
  (
    {
      id: "fixture",
      platform: "linux-x64",
      url: "https://example.invalid/runtime.tar.gz",
      sha256: checksum(archive),
      moonbit_version: "fixture-sdk",
    },
    archive,
  )
}

///|
async fn fixture_toolchain(destination : String, _version : String) -> Unit {
  @fs.mkdir(destination + "/bin", recursive=true)
  @fs.mkdir(destination + "/lib/core", recursive=true)
  for name in ["moon", "moonc", "moonrun", "moonx"] {
    @fs.write_file(
      destination + "/bin/" + name,
      "#!/bin/sh\nprintf 'fixture-sdk\\n'\n",
      permission=0o755,
    )
  }
}

///|
async test "setup publishes a verified runtime and reuses it without downloading" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let root = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(root, recursive=true)
  let (info, archive) = fixture(root)
  let installs = Ref(0)
  let toolchain : async (String, String) -> Unit = (destination, version) => {
    installs.val += 1
    fixture_toolchain(destination, version)
  }
  let downloads = Ref(0)
  let fetch : async (String, String) -> Unit = (_url, target) => {
    downloads.val += 1
    ignore(command("cp", [archive, target]))
  }
  let (installed, reused) = install(
    info,
    root + "/runtime",
    _ => (),
    download=fetch,
    toolchain~,
  )
  assert_false(reused)
  assert_eq(
    @fs.read_file(installed + "/share/doc/moonbit/index.md").text(),
    "resource",
  )
  let (again, reused) = install(
    info,
    root + "/runtime",
    _ => (),
    download=fetch,
    toolchain~,
  )
  assert_true(reused)
  assert_eq(again, installed)
  assert_eq(downloads.val, 1)
  assert_eq(installs.val, 1)
  assert_eq(@fs.readdir(root + "/runtime", include_hidden=true).length(), 2)
}

///|
async test "bad download never publishes and retry succeeds without replacing another runtime" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let root = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(root, recursive=true)
  let (info, archive) = fixture(root)
  let base = root + "/runtime"
  @fs.mkdir(base + "/existing", recursive=true)
  @fs.write_file(base + "/existing/marker", "keep")
  let result = try {
    install(
      info,
      base,
      _ => (),
      download=(_url, target) => @fs.write_file(target, "truncated"),
      toolchain=fixture_toolchain,
    )
    |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(result.contains("checksum mismatch"))
  assert_false(@fs.exists(base + "/" + info.sha256))
  assert_false(
    @fs.readdir(base, include_hidden=true).any(name => {
      name.has_prefix(".setup-")
    }),
  )
  let (_, reused) = install(
    info,
    base,
    _ => (),
    download=(_url, target) => ignore(command("cp", [archive, target])),
    toolchain=fixture_toolchain,
  )
  assert_false(reused)
  assert_eq(@fs.read_file(base + "/existing/marker").text(), "keep")
}

///|
async test "concurrent setup callers share one completed installation" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let root = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(root, recursive=true)
  let (info, archive) = fixture(root)
  let downloads = Ref(0)
  let fetch : async (String, String) -> Unit = (_url, target) => {
    downloads.val += 1
    ignore(command("cp", [archive, target]))
  }
  @async.with_task_group(group => {
    let first = group.spawn(() => {
      install(
        info,
        root + "/runtime",
        _ => (),
        download=fetch,
        toolchain=fixture_toolchain,
      )
    })
    let second = group.spawn(() => {
      install(
        info,
        root + "/runtime",
        _ => (),
        download=fetch,
        toolchain=fixture_toolchain,
      )
    })
    let (a, reused_a) = first.wait()
    let (b, reused_b) = second.wait()
    assert_eq(a, b)
    assert_true(reused_a != reused_b)
  })
  assert_eq(downloads.val, 1)
}

///|
test "release metadata requires a supported platform HTTPS and an exact checksum" {
  let valid : Json = {
    "id": "cli-v1",
    "platform": "linux-x64",
    "url": "https://example.invalid/runtime",
    "sha256": "a".repeat(64),
    "moonbit_version": "fixture-sdk",
  }
  assert_eq(decode_release(valid.stringify()).id, "cli-v1")
  for
    (key, value) in [
      ("platform", "macos"),
      ("url", "http://example.invalid/runtime"),
      ("sha256", "abc"),
    ] {
    guard valid is Object(fields) else { fail("object expected") }
    let changed = fields.copy()
    changed[key] = Json(value)
    let refused = try {
      decode_release(Json(changed).stringify()) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
async test "failed official installer leaves no completed runtime and can retry" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let root = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(root, recursive=true)
  let (info, archive) = fixture(root)
  let base = root + "/runtime"
  let fetch : async (String, String) -> Unit = (_url, target) => {
    ignore(command("cp", [archive, target]))
  }
  let refused = try {
    install(info, base, _ => (), download=fetch, toolchain=(
      destination,
      _version,
    ) => {
      @fs.mkdir(destination, recursive=true)
      @fs.write_file(destination + "/partial", "interrupted installer")
      fail("installer failed")
    })
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  assert_false(@fs.exists(base + "/" + info.sha256))
  assert_eq(@fs.readdir(base, include_hidden=true), ["setup.lock"])
  let (_, reused) = install(
    info,
    base,
    _ => (),
    download=fetch,
    toolchain=fixture_toolchain,
  )
  assert_false(reused)
}
