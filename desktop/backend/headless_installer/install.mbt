///|
fn installation(
  reply : Json,
  manifest : Manifest,
  digest : String,
  home : String,
) -> Installation raise {
  guard reply
    is {
      "status": String(status),
      "build_id": String(build),
      "platform": String(platform),
      "manifest_sha256": String(actual_digest),
      "launcher": String(launcher),
      ..
    } &&
    (status == "installed" || status == "reused") &&
    build == manifest.build_id &&
    platform == manifest.platform &&
    actual_digest == digest &&
    launcher.has_prefix("/") else {
    raise InstallError(
      "verify_remote", "Installer returned a different artifact identity",
    )
  }
  {
    build_id: build,
    platform,
    manifest_sha256: digest,
    launcher,
    home,
    reused: status == "reused",
  }
}

///|
/// Upload an explicitly selected local development artifact. The bootstrap is
/// shipped with the application; remote output never chooses code or a URL.
pub async fn install(
  destination~ : String,
  directory~ : String,
  bootstrap~ : String,
  ssh~ : String = "ssh",
  root? : String,
  progress~ : (String) -> Unit = _ => (),
) -> Installation {
  let stage = Ref("verify_local")
  fn advance(value : String) -> Unit {
    stage.val = value
    progress(value)
  }
  try {
    advance("verify_local")
    guard !bootstrap.is_empty() &&
      bootstrap.length() < 65536 &&
      !bootstrap.contains("\u0000") else {
      raise InstallError(
        "prepare", "Packaged installer script is missing or invalid",
      )
    }
    let directory = @fs.realpath(directory)
    let manifest_path = @pathx.Path(directory).join("manifest.json").to_string()
    guard @fs.kind(manifest_path, follow_symlink=false) is Regular &&
      @fs.file_size(manifest_path) <= 8L * 1024L * 1024L else {
      raise InstallError(
        "verify_local", "Invalid manifest or manifest size limit exceeded",
      )
    }
    let bytes = @fs.read_file(manifest_path).binary()
    let manifest = manifest(@json.parse(@utf8.decode(bytes)))
    let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    verify_tree(directory, manifest)
    advance("probe")
    let info = bootstrap_request(
      bootstrap,
      destination,
      { "action": "probe" },
      ssh~,
    )
    guard info is { "platform": String(platform), "home": String(home), .. } &&
      platform == manifest.platform &&
      home.has_prefix("/") else {
      raise InstallError(
        "probe", "Working-host platform or home does not match the package",
      )
    }
    let root = root.unwrap_or(home + "/.local/share/seekmoon/host-packages")
    guard root.has_prefix("/") && !root.split("/").any(part => part == "..") else {
      raise InstallError(
        "prepare", "Install root must be absolute without parent traversal",
      )
    }
    let expected : Map[String, Json] = {
      "root": Json(root),
      "build_id": Json(manifest.build_id),
      "platform": Json(manifest.platform),
      "manifest_sha256": Json(digest),
    }
    advance("inspect")
    let inspect_request = expected.copy()
    inspect_request["action"] = "inspect"
    let existing = bootstrap_request(
      bootstrap,
      destination,
      Json(inspect_request),
      ssh~,
    )
    if existing is { "status": "reused", .. } {
      return installation(existing, manifest, digest, home)
    }
    guard existing is { "status": "missing", .. } else {
      raise InstallError("inspect", "Unexpected installed-package state")
    }
    let temporary = @fs.tmpdir(prefix="seekmoon-upload-")
    defer @fs.rmdir(temporary, recursive=true)
    let archive = @pathx.Path(temporary).join("package.tar.gz").to_string()
    advance("archive")
    let (code, _, errors) = @async.with_timeout(600000, () => {
      @processx.collect_output_no_stdin(
        "tar",
        ["-czf", archive, "-C", directory, "."],
        extra_env={ "COPYFILE_DISABLE": "1" },
      )
    })
    guard code == 0 else {
      raise InstallError(
        "archive",
        "Could not create package archive: " + errors.text(),
      )
    }
    let (size, hash) = hash_file(archive, 1024L * 1024L * 1024L)
    guard size > 0 else {
      raise InstallError("archive", "Package archive is empty")
    }
    let request = expected.copy()
    request["action"] = "install"
    request["archive_size"] = Json(size.to_int())
    request["archive_sha256"] = Json(hash)
    advance("upload")
    let reply = bootstrap_request(
      bootstrap,
      destination,
      Json(request),
      ssh~,
      archive~,
    )
    let result = installation(reply, manifest, digest, home)
    advance("verified")
    result
  } catch {
    InstallError(_, _) as error => raise error
    error => raise InstallError(stage.val, "\{error}")
  }
}
