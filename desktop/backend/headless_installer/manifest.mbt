///|
priv struct Entry {
  size : Int64
  mode : Int32
  sha256 : String
}

///|
priv struct Manifest {
  build_id : String
  platform : String
  files : Map[String, Entry]
}

///|
fn digest_valid(value : String) -> Bool {
  value.length() == 64 &&
  value.iter().all(ch => ch is ('0'..<='9' | 'a'..<='f'))
}

///|
fn path_valid(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 1024 &&
  !value.iter().any(ch => ch is ('\u0000'..<='\u001f' | '\u007f' | '\\')) &&
  value.split("/").all(part => part != "" && part != "." && part != "..")
}

///|
fn manifest(value : Json) -> Manifest raise {
  guard value
    is {
      "schema_version": 1,
      "protocol_version": 1,
      "data_schema_version": 1,
      "build_id": String(build),
      "platform": String(platform),
      "moonbit_version": String(version),
      "resource_sha256": String(resources),
      "runtime_requirements": {
        "os": "Linux",
        "libc": "glibc",
        "minimum_glibc": "2.35",
        ..
      },
      "files": Array(files),
      ..
    } &&
    !build.is_empty() &&
    build.length() <= 200 &&
    !build.has_prefix(".") &&
    !build.has_prefix("-") &&
    !build.has_prefix("_") &&
    build
    .iter()
    .all(ch => ch is ('0'..<='9' | 'a'..<='z' | 'A'..<='Z' | '.' | '-' | '_')) &&
    (platform == "linux-x64" || platform == "linux-arm64") &&
    !version.is_empty() &&
    digest_valid(resources) else {
    raise InstallError(
      "verify_local", "Invalid headless manifest or unsupported runtime requirements",
    )
  }
  guard !files.is_empty() && files.length() <= 100000 else {
    raise InstallError("verify_local", "Manifest file count exceeds its limit")
  }
  let entries : Map[String, Entry] = Map([])
  let mut total = 0L
  for file in files {
    guard file
      is {
        "path": String(path),
        "size": Number(size, ..),
        "mode": Number(mode, ..),
        "sha256": String(hash),
        ..
      } &&
      path_valid(path) &&
      path != "manifest.json" &&
      !entries.contains(path) &&
      size >= 0 &&
      size <= 4294967296 &&
      size == size.to_int64().to_double() &&
      (mode == 420 || mode == 493) &&
      digest_valid(hash) else {
      raise InstallError("verify_local", "Invalid or duplicate manifest file")
    }
    total += size.to_int64()
    guard total <= 4294967296L else {
      raise InstallError(
        "verify_local", "Expanded package size exceeds its limit",
      )
    }
    guard path != "web/frontend.js" &&
      !path
      .split("/")
      .any(part => {
        ["cef", "chromium embedded framework", "libcef.so", "proton"].contains(
          part.to_owned().to_lower(),
        )
      }) else {
      raise InstallError(
        "verify_local", "GUI payload is not a headless package",
      )
    }
    entries[path] = {
      size: size.to_int64(),
      mode: mode.to_int(),
      sha256: hash,
    }
  }
  let seed = "toolchains/moonbit/" + platform
  let executables = ["bin/openseek", "bin/moonrun", "bin/rg"] +
    ["moon", "moonc", "moonx", "moonrun"].map(name => seed + "/bin/" + name)
  for
    name in executables +
    [
      "lib/openseek.wasm",
      "share/doc/moonbit/index.md",
      "web/viz/index.html",
      "web/viz/viz_app.js",
      seed + "/.openseek-moonbit-seed-version",
    ] {
    guard entries.contains(name) else {
      raise InstallError("verify_local", "Missing headless resource: " + name)
    }
  }
  for name in executables {
    guard entries.get(name) is Some({ mode: 493, .. }) else {
      raise InstallError("verify_local", "Invalid executable mode: " + name)
    }
  }
  guard entries.contains(seed + "/lib/core/moon.mod") ||
    entries.contains(seed + "/lib/core/moon.mod.json") else {
    raise InstallError("verify_local", "Missing MoonBit core module")
  }
  { build_id: build, platform, files: entries, }
}

///|
async fn hash_file(path : String, limit : Int64) -> (Int64, String) {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let hash = @crypto.SHA256::new()
  let mut size = 0L
  while file.read_some(max_len=65536) is Some(bytes) {
    size += bytes.length().to_int64()
    guard size <= limit else {
      raise InstallError("verify_local", "File size limit exceeded: " + path)
    }
    hash.update_from_iter(bytes.iter())
  }
  (size, @crypto.bytes_to_hex_string(hash.finalize()))
}

///|
/// Manifest permissions are applied and verified on the Linux host. Local
/// filesystems need only preserve file bytes, so extracted packages also work
/// on clients that cannot represent Unix executable bits.
async fn verify_tree(root : String, manifest : Manifest) -> Unit {
  let directories = [""]
  let seen : Set[String] = Set([])
  let mut count = 0
  while directories.pop() is Some(prefix) {
    let path = @pathx.Path(root).join(prefix).to_string()
    let directory = @fs.opendir(path)
    defer directory.close()
    while directory.next(include_hidden=true) is Some(entry) {
      count += 1
      let relative = if prefix.is_empty() {
        entry.name
      } else {
        prefix + "/" + entry.name
      }
      guard count <= 200000 && path_valid(relative) else {
        raise InstallError(
          "verify_local", "Invalid package path or entry limit exceeded",
        )
      }
      let path = @pathx.Path(root).join(relative).to_string()
      match @fs.kind(path, follow_symlink=false) {
        Directory => directories.push(relative)
        Regular => {
          if relative == "manifest.json" {
            continue
          }
          guard manifest.files.get(relative) is Some(expected) else {
            raise InstallError(
              "verify_local",
              "Unexpected package file: " + relative,
            )
          }
          let (size, hash) = hash_file(path, expected.size)
          guard size == expected.size && hash == expected.sha256 else {
            raise InstallError(
              "verify_local",
              "Package checksum mismatch: " + relative,
            )
          }
          seen.add(relative)
        }
        _ =>
          raise InstallError(
            "verify_local",
            "Package links and special files are unsupported: " + relative,
          )
      }
    }
  }
  guard seen.length() == manifest.files.length() else {
    raise InstallError("verify_local", "Package file set is incomplete")
  }
}
