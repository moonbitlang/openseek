///|
async fn executable(path : String, text : String) -> Unit {
  @fs.write_file(path, "#!/bin/sh\nprintf '\{text}\\n'\n", permission=0o755)
}

///|
async fn fixture_toolchain(destination : String) -> Unit {
  @fs.mkdir(destination + "/bin", recursive=true, allow_exist=true)
  @fs.mkdir(destination + "/lib/core", recursive=true, allow_exist=true)
  for name in ["moon", "moonc", "moonrun", "moonx"] {
    executable(destination + "/bin/" + name, "existing-sdk")
  }
}

///|
async fn fixture_bundle(destination : String) -> Unit {
  @fs.mkdir(destination + "/bin", recursive=true, allow_exist=true)
  executable(destination + "/bin/rg", "fixture-rg")
  for directory in ["doc/moonbit/language", "doc/moonbit/toolchain", "workflow"] {
    @fs.mkdir(
      destination + "/share/" + directory,
      recursive=true,
      allow_exist=true,
    )
  }
  for file in resource_files() {
    @fs.write_file(destination + "/share/" + file, "resource")
  }
  @fs.mkdir(destination + "/licenses", allow_exist=true)
  @fs.write_file(destination + "/licenses/LICENSE", "fixture license")
}

///|
async fn isolated_available(program : String, args : Array[String]) -> Bool {
  program.contains("/") && usable(program, args)
}

///|
async test "setup installs missing dependencies and reuses them offline" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  assert_false(
    install(
      home,
      home + "/bootstrap.wasm",
      _ => (),
      available=isolated_available,
      bundle=fixture_bundle,
      cli=path => executable(path, "fixture-cli"),
      toolchain=fixture_toolchain,
    ),
  )
  assert_true(usable(home + "/.moon/bin/moon", ["version"]))
  assert_true(usable(home + "/.openseek/bin/openseek", ["--help"]))
  assert_true(usable(home + "/.openseek/bin/rg", ["--version"]))
  assert_true(resources_available(home + "/.openseek/share"))
  assert_eq(
    @fs.read_file(home + "/.openseek/share/licenses/LICENSE").text(),
    "fixture license",
  )
  assert_true(
    install(
      home,
      home + "/bootstrap.wasm",
      _ => (),
      available=isolated_available,
      bundle=_ => fail("must not download"),
      cli=_ => fail("must not download CLI"),
      toolchain=_ => fail("must not reinstall SDK"),
    ),
  )
}

///|
async test "setup reuses PATH tools and preserves existing resource files" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  @fs.mkdir(home + "/.openseek/share/doc/moonbit", recursive=true)
  @fs.write_file(
    home + "/.openseek/share/doc/moonbit/index.md",
    "user documentation",
  )
  executable(home + "/bootstrap", "bootstrap-cli")
  assert_false(
    install(
      home,
      home + "/bootstrap",
      _ => (),
      available=(program, args) => {
        if ["moon", "moonc", "moonrun", "moonx", "rg"].contains(program) {
          true
        } else {
          isolated_available(program, args)
        }
      },
      bundle=fixture_bundle,
      cli=_ => fail("must copy the current CLI"),
      toolchain=_ => fail("working SDK must be reused"),
    ),
  )
  assert_false(@fs.exists(home + "/.moon"))
  assert_false(@fs.exists(home + "/.openseek/bin/rg"))
  assert_eq(
    command(home + "/.openseek/bin/openseek", ["--help"]),
    "bootstrap-cli\n",
  )
  assert_eq(
    @fs.read_file(home + "/.openseek/share/doc/moonbit/index.md").text(),
    "user documentation",
  )
  assert_true(resources_available(home + "/.openseek/share"))
}

///|
async test "setup repairs only an unusable tool without replacing working dependencies" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  fixture_toolchain(home + "/.moon")
  fixture_bundle(home + "/.openseek")
  executable(home + "/.openseek/bin/openseek", "keep-cli")
  @fs.write_file(
    home + "/.openseek/bin/rg",
    "#!/bin/sh\nexit 1\n",
    permission=0o644,
  )
  @fs.write_file(home + "/.moon/credentials", "keep")
  @fs.write_file(home + "/.openseek/share/doc/moonbit/index.md", "keep-docs")
  assert_false(
    install(
      home,
      home + "/bootstrap",
      _ => (),
      available=isolated_available,
      bundle=fixture_bundle,
      cli=path => executable(path, "fixture-cli"),
      toolchain=_ => fail("SDK must not be replaced"),
    ),
  )
  assert_eq(command(home + "/.openseek/bin/rg", ["--version"]), "fixture-rg\n")
  assert_eq(command(home + "/.openseek/bin/openseek", ["--help"]), "keep-cli\n")
  assert_eq(@fs.kind(home + "/.moon/lib/core"), Directory)
  assert_eq(@fs.read_file(home + "/.moon/credentials").text(), "keep")
  assert_eq(
    @fs.read_file(home + "/.openseek/share/doc/moonbit/index.md").text(),
    "keep-docs",
  )
}

///|
async test "corrupt bundle is rejected before extraction" {
  let destination = @fs.tmpdir(prefix="openseek-bundle-test-")
  defer @fs.rmdir(destination, recursive=true)
  let error = try {
    extract_bundle(
      { url: "https://example.invalid/bundle.tar.gz", sha256: "a".repeat(64), },
      destination,
      download=(_url, path) => @fs.write_file(path, "corrupt"),
    )
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(error.contains("checksum mismatch"))
}

///|
async test "failed SDK installation remains retryable without a completion stamp" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let error = try {
    install(
      home,
      home + "/bootstrap",
      _ => (),
      available=isolated_available,
      bundle=_ => fail("SDK failure must stop setup"),
      cli=path => executable(path, "fixture-cli"),
      toolchain=destination => {
        fixture_toolchain(destination)
        @fs.rmdir(destination + "/lib/core", recursive=true)
        @fs.write_file(destination + "/credentials", "keep")
        fail("installer failed")
      },
    )
    |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(error.contains("installer failed"))
  assert_false(
    install(
      home,
      home + "/bootstrap",
      _ => (),
      available=isolated_available,
      bundle=fixture_bundle,
      cli=path => executable(path, "fixture-cli"),
      toolchain=fixture_toolchain,
    ),
  )
  assert_eq(@fs.kind(home + "/.moon/lib/core"), Directory)
  assert_eq(@fs.read_file(home + "/.moon/credentials").text(), "keep")
}

///|
async test "concurrent setup checks installed files again after taking the lock" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let downloads = Ref(0)
  let setup : async () -> Bool = () => {
    install(
      home,
      home + "/bootstrap",
      _ => (),
      available=isolated_available,
      bundle=destination => {
        downloads.val += 1
        fixture_bundle(destination)
      },
      cli=path => executable(path, "fixture-cli"),
      toolchain=fixture_toolchain,
    )
  }
  @async.with_task_group(group => {
    let first = group.spawn(setup)
    let second = group.spawn(setup)
    assert_true(first.wait() != second.wait())
  })
  assert_eq(downloads.val, 1)
}

///|
test "bundle checksum selects the exact platform asset and rejects invalid or missing entries" {
  let filename = "openseek-deps-linux-x64.tar.gz"
  let digest = "a".repeat(64)
  let sums = "b".repeat(64) +
    "  openseek-deps-linux-arm64.tar.gz\n" +
    digest +
    "  " +
    filename +
    "\n"
  assert_eq(bundle_checksum(sums, filename), digest)
  for
    source in [
      "",
      "bad  " + filename,
      "z".repeat(64) + "  " + filename,
      digest + "  " + filename + ".old",
    ] {
    let refused = try {
      bundle_checksum(source, filename) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "setup selects every official native toolchain platform" {
  for
    (host, platform) in [
      ("Linux x86_64", "linux-x64"),
      ("Linux aarch64", "linux-arm64"),
      ("Darwin arm64", "macos-arm64"),
      ("Windows AMD64", "windows-x64"),
      // The official installer supplies the x64 toolchain on ARM64 Windows.
      ("Windows ARM64", "windows-x64"),
    ] {
    assert_eq(host_platform(host), platform)
  }
  let refused = try {
    host_platform("Windows x86") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
async test "missing CLI downloads separately without fetching an available dependency bundle" {
  if is_windows() {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-cli-test-")
  defer @fs.rmdir(home, recursive=true)
  fixture_toolchain(home + "/.moon")
  fixture_bundle(home + "/.openseek")
  assert_false(@fs.exists(home + "/.openseek/bin/openseek"))
  assert_false(
    install(
      home,
      home + "/bootstrap.wasm",
      _ => (),
      available=isolated_available,
      bundle=_ => fail("must reuse installed dependencies"),
      toolchain=_ => fail("must reuse installed SDK"),
      cli=path => executable(path, "downloaded-cli"),
    ),
  )
  assert_eq(
    command(home + "/.openseek/bin/openseek", ["--help"]),
    "downloaded-cli\n",
  )
}

///|
test "setup selects CLI and dependencies from the shared release manifest" {
  let digest = "a".repeat(64)
  let base = "https://downloads.example.com/openseek/staging/desktop/releases/v0.2.0/"
  let manifest : Json = {
    "version": "0.2.0",
    "platforms": {
      "macos-arm64": { "url": base + "SeekMoon.app.zip", "sha256": digest },
      "cli-macos-arm64": {
        "url": base + "openseek-macos-arm64",
        "sha256": digest,
      },
      "cli-deps-macos-arm64": {
        "url": base + "openseek-deps-macos-arm64.tar.gz",
        "sha256": digest,
      },
    },
  }
  for
    (key, filename) in [
      ("cli-macos-arm64", "openseek-macos-arm64"),
      ("cli-deps-macos-arm64", "openseek-deps-macos-arm64.tar.gz"),
    ] {
    let artifact = manifest_artifact(manifest, key)
    assert_eq(artifact.url, base + filename)
    assert_eq(artifact.sha256, digest)
  }
}

///|
test "setup rejects absent or malformed release artifacts before downloading" {
  let manifests : Array[Json] = [
    { "platforms": {} },
    { "platforms": { "cli-linux-x64": { "url": "https://example.com/cli" } } },
    {
      "platforms": {
        "cli-linux-x64": {
          "url": "http://example.com/cli",
          "sha256": "a".repeat(64),
        },
      },
    },
    {
      "platforms": {
        "cli-linux-x64": { "url": "https://example.com/cli", "sha256": "a" },
      },
    },
    {
      "platforms": {
        "cli-linux-x64": {
          "url": "https://example.com/cli",
          "sha256": "z".repeat(64),
        },
      },
    },
  ]
  for manifest in manifests {
    let rejected = try {
      manifest_artifact(manifest, "cli-linux-x64") |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
