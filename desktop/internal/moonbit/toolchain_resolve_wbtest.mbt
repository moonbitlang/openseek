///|
async fn remove_toolchain_test_tree(root : @path.Path) -> Unit {
  @fs.rmdir(root.to_string(), recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// Runs `body` against a fresh temporary root and removes the tree on both
/// exit paths — `defer` cannot run the async removal, so the try/catch
/// split lives here once instead of in every test.
async fn with_toolchain_test_tree(body : async (@path.Path) -> Unit) -> Unit {
  let root = @path.Path(@fs.tmpdir(prefix="openseek-moonbit-external-"))
  body(root) catch {
    error => {
      remove_toolchain_test_tree(root)
      raise error
    }
  }
  remove_toolchain_test_tree(root)
}

///|
/// A complete fake toolchain: the resolver only assembles one around the
/// executable the desktop spawns — `moon`.
async fn touch_fake_toolchain(bin_dir : @path.Path) -> Unit {
  @fs.write_file(
    bin_dir.join("moon" + ExecutableSuffix).to_string(),
    "",
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
}

///|
#cfg(not(platform="windows"))
async test "a non-executable moon file does not count" {
  with_toolchain_test_tree(async fn(root) {
    let path_bin = root.join("pathdir")
    let home_bin = root.join("home").join(".moon").join("bin")
    @fs.mkdir(path_bin.to_string(), recursive=true)
    @fs.mkdir(home_bin.to_string(), recursive=true)
    @fs.write_file(
      path_bin.join("moon").to_string(),
      "",
      create_mode=CreateOrTruncate,
    )
    touch_fake_toolchain(home_bin)
    let toolchain = external_toolchain(
      path_env=path_bin.to_string(),
      home_dir=root.join("home"),
    )
    assert_eq(toolchain.bin_dir.to_string(), home_bin.to_string())
  })
}

///|
async test "a directory named moon does not count" {
  with_toolchain_test_tree(async fn(root) {
    let path_bin = root.join("pathdir")
    let home_bin = root.join("home").join(".moon").join("bin")
    @fs.mkdir(
      path_bin.join("moon" + ExecutableSuffix).to_string(),
      recursive=true,
    )
    @fs.mkdir(home_bin.to_string(), recursive=true)
    touch_fake_toolchain(home_bin)
    let toolchain = external_toolchain(
      path_env=path_bin.to_string(),
      home_dir=root.join("home"),
    )
    assert_eq(toolchain.bin_dir.to_string(), home_bin.to_string())
  })
}

///|
async test "an executable moon is a usable toolchain" {
  with_toolchain_test_tree(async fn(root) {
    let bin_dir = root.join("bin")
    @fs.mkdir(bin_dir.to_string(), recursive=true)
    @fs.write_file(
      bin_dir.join("moon" + ExecutableSuffix).to_string(),
      "",
      create_mode=CreateOrTruncate,
      permission=0o755,
    )
    assert_true(toolchain_at(bin_dir) is Some(_))
  })
}

///|
async test "a file-shaped path entry does not abort the scan" {
  with_toolchain_test_tree(async fn(root) {
    let not_a_dir = root.join("notdir")
    let home_bin = root.join("home").join(".moon").join("bin")
    @fs.write_file(not_a_dir.to_string(), "", create_mode=CreateOrTruncate)
    @fs.mkdir(home_bin.to_string(), recursive=true)
    touch_fake_toolchain(home_bin)
    let toolchain = external_toolchain(
      path_env=not_a_dir.to_string(),
      home_dir=root.join("home"),
    )
    assert_eq(toolchain.bin_dir.to_string(), home_bin.to_string())
  })
}

///|
async test "path scan wins over the default install" {
  with_toolchain_test_tree(async fn(root) {
    let home_bin = root.join("home").join(".moon").join("bin")
    let path_bin = root.join("pathdir")
    @fs.mkdir(home_bin.to_string(), recursive=true)
    @fs.mkdir(path_bin.to_string(), recursive=true)
    touch_fake_toolchain(home_bin)
    touch_fake_toolchain(path_bin)
    let toolchain = external_toolchain(
      path_env=path_bin.to_string(),
      home_dir=root.join("home"),
    )
    assert_eq(toolchain.bin_dir.to_string(), path_bin.to_string())
  })
}

///|
async test "no toolchain anywhere raises ToolchainUnavailable" {
  with_toolchain_test_tree(async fn(root) {
    let bare_bin = root.join("bare")
    @fs.mkdir(bare_bin.to_string(), recursive=true)
    try
      external_toolchain(
        path_env=bare_bin.to_string(),
        home_dir=root.join("home"),
      )
    catch {
      ToolchainUnavailable => ()
      error => raise error
    } noraise {
      _ => fail("resolved without any toolchain present")
    }
  })
}

///|
/// The environment policy is a path prepend and nothing else — in
/// particular the ambient `MOON_HOME` must survive untouched, or spawned
/// sessions lose the user's registry credentials.
async test "toolchain env policy leaves MOON_HOME alone" {
  let env : Map[String, String] = { "MOON_HOME": "/custom", "PATH": "/usr/bin" }
  { bin_dir: Path("/found/bin"), moon: Path("/found/bin/moon") }.apply_to_env(
    env,
  )
  assert_eq(env.get("MOON_HOME"), Some("/custom"))
  assert_true(env.get("PATH").unwrap_or("").has_prefix("/found/bin"))
}
