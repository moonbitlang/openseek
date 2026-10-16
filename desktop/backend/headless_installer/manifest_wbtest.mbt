///|
fn fixture_files() -> Array[String] {
  let seed = "toolchains/moonbit/linux-x64"
  [
    "bin/openseek",
    "bin/moonrun",
    "bin/rg",
    "lib/openseek.wasm",
    "share/doc/moonbit/index.md",
    "web/viz/index.html",
    "web/viz/viz_app.js",
    seed + "/bin/moon",
    seed + "/bin/moonc",
    seed + "/bin/moonx",
    seed + "/bin/moonrun",
    seed + "/.openseek-moonbit-seed-version",
    seed + "/lib/core/moon.mod",
  ]
}

///|
fn fixture_manifest(files : Array[Json]) -> Json {
  {
    "schema_version": 1,
    "protocol_version": 1,
    "data_schema_version": 1,
    "build_id": "test-build",
    "platform": "linux-x64",
    "moonbit_version": "test-sdk",
    "resource_sha256": @crypto.bytes_to_hex_string(@crypto.sha256(b"x")),
    "runtime_requirements": {
      "os": "Linux",
      "libc": "glibc",
      "minimum_glibc": "2.35",
    },
    "files": files,
  }
}

///|
fn fixture_entries() -> Array[Json] {
  fixture_files().map(path => {
    let mode = if path.has_prefix("bin/") ||
      path.has_prefix("libexec/") ||
      path.contains("/bin/") {
      493
    } else {
      420
    }
    {
      "path": path,
      "mode": mode,
      "size": 1,
      "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(b"x")),
    }
  })
}

///|
async fn fixture_package(root : String) -> Json {
  for path in fixture_files() {
    let full = @pathx.Path(root).join(path)
    @fs.mkdir(full.dirname().to_string(), recursive=true, allow_exist=true)
    @fs.write_file(full.to_string(), "x")
  }
  let value = fixture_manifest(fixture_entries())
  @fs.write_file(root + "/manifest.json", value.stringify())
  value
}

///|
test "native manifest rejects traversal duplicates missing resources and invalid modes" {
  let valid = fixture_entries()
  ignore(manifest(fixture_manifest(valid)))
  for
    files in [
      valid +
      [
        {
          "path": "../outside",
          "size": 0,
          "mode": 420,
          "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(b"")),
        },
      ],
      valid + [valid[0]],
      valid[1:].to_owned(),
      [
        {
          "path": "bin/openseek",
          "size": 1,
          "mode": 420,
          "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(b"x")),
        },
      ] +
      valid[1:].to_owned(),
    ] {
    let rejected = try {
      ignore(manifest(fixture_manifest(files)))
      false
    } catch {
      InstallError(_, _) => true
      error => raise error
    }
    assert_true(rejected)
  }
}

///|
#cfg(not(platform="windows"))
async test "native verification rejects corruption extra files and links before SSH" {
  let root = @fs.tmpdir(prefix="native-install-package-")
  defer @fs.rmdir(root, recursive=true)
  let value = fixture_package(root)
  verify_tree(root, manifest(value))
  @fs.write_file(root + "/bin/openseek", "y")
  let rejected = try {
    ignore(
      install(
        destination="host",
        directory=root,
        bootstrap="unused",
        ssh="/must-not-be-invoked",
      ),
    )
    false
  } catch {
    InstallError(stage, message) =>
      stage == "verify_local" && message.contains("checksum")
    error => raise error
  }
  assert_true(rejected)
  @fs.write_file(root + "/bin/openseek", "x")
  @fs.write_file(root + "/extra", "extra")
  for linked in [false, true] {
    if linked {
      @fs.remove(root + "/extra")
      @fs.symlink(root + "/extra", target=root + "/bin/openseek")
    }
    let rejected = try {
      verify_tree(root, manifest(value))
      false
    } catch {
      InstallError(_, _) => true
      error => raise error
    }
    assert_true(rejected)
  }
}
