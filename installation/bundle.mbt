///|
priv struct Bundle {
  url : String
  sha256 : String
}

///|
fn bundle_checksum(source : String, filename : String) -> String raise {
  for line in source.split("\n") {
    if line.length() > 66 && line[64:66] == "  " && line[66:] == filename {
      let digest = line[:64].to_owned()
      guard digest.iter().all(c => c is ('0'..<='9' | 'a'..<='f')) else {
        fail("invalid SHA256SUMS entry for \{filename}")
      }
      return digest
    }
  }
  fail("SHA256SUMS has no entry for \{filename}")
}

///|
fn host_platform(system : String) -> String raise {
  match system {
    "Linux x86_64" => "linux-x64"
    "Linux aarch64" => "linux-arm64"
    "Darwin arm64" => "macos-arm64"
    "Windows AMD64" | "Windows ARM64" => "windows-x64"
    _ => fail("unsupported installation platform: \{system}")
  }
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
async fn extract_bundle(
  info : Bundle,
  destination : String,
  download~ : async (String, String) -> Unit,
) -> Unit {
  let archive = destination + "/bundle.tar.gz"
  download(info.url, archive)
  guard checksum(archive) == info.sha256 else {
    fail("installation bundle checksum mismatch")
  }
  ignore(command("tar", ["-xzf", archive, "-C", destination]))
}

///|
fn manifest_artifact(manifest : Json, key : String) -> Bundle raise {
  guard manifest is { "platforms": Object(platforms), .. } &&
    platforms.get(key)
    is Some({ "url": String(url), "sha256": String(sha256), .. }) else {
    fail("release manifest has no artifact for \{key}")
  }
  guard url.has_prefix("https://") &&
    sha256.length() == 64 &&
    sha256.iter().all(c => c is ('0'..<='9' | 'a'..<='f')) else {
    fail("invalid release artifact for \{key}")
  }
  { url, sha256, }
}

///|
async fn download_source(
  key : String,
  filename : String,
  bundle_url : String?,
  manifest : Ref[Json?],
) -> Bundle {
  if bundle_url is Some(url) {
    guard url.has_prefix("https://") && url.rev_find("/") is Some(index) else {
      fail("--bundle-url requires HTTPS")
    }
    let base = url[:index].to_owned()
    let sha256 = bundle_checksum(
      command("curl", curl_args(base + "/SHA256SUMS")),
      filename,
    )
    return {
      url: if key.has_prefix("cli-deps-") {
        url
      } else {
        base + "/" + filename
      },
      sha256,
    }
  }
  let release = match manifest.val {
    Some(value) => value
    None => {
      let origin = @env.get_env_var("OPENSEEK_API_ORIGIN").unwrap_or(
        "https://openseek-api.moonbitlang.cn",
      )
      guard origin.has_prefix("https://") else {
        fail("OPENSEEK_API_ORIGIN requires HTTPS")
      }
      let value = @json.parse(
        command("curl", curl_args(origin + "/desktop/releases/latest.json")),
      )
      manifest.val = Some(value)
      value
    }
  }
  manifest_artifact(release, key)
}

///|
async fn current_platform() -> String {
  host_platform(
    if is_windows() {
      "Windows " +
      @env.get_env_var("PROCESSOR_ARCHITEW6432").unwrap_or(
        @env.get_env_var("PROCESSOR_ARCHITECTURE").unwrap_or(""),
      )
    } else {
      command("uname", ["-sm"]).trim().to_owned()
    },
  )
}

///|
async fn download_bundle(
  destination : String,
  bundle_url : String?,
  manifest : Ref[Json?],
) -> Unit {
  let platform = current_platform()
  let info = download_source(
    "cli-deps-" + platform,
    "openseek-deps-" + platform + ".tar.gz",
    bundle_url,
    manifest,
  )
  extract_bundle(info, destination, download=download_file)
}

///|
async fn download_cli(
  destination : String,
  bundle_url : String?,
  manifest : Ref[Json?],
) -> Unit {
  let platform = current_platform()
  let info = download_source(
    "cli-" + platform,
    executable_name("openseek-" + platform),
    bundle_url,
    manifest,
  )
  download_file(info.url, destination)
  guard checksum(destination) == info.sha256 else {
    fail("openseek checksum mismatch")
  }
  if !is_windows() {
    @fs.chmod(destination, 0o755)
  }
}
