///|
async fn remove_toolchain_test_tree(root : @pathx.Absolute) -> Unit nocancel {
  @async.protect_from_cancel(() => {
    @fs.rmdir(root.to_string(), recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// Runs `body` against a fresh temporary root and removes the tree on both
/// exit paths, so no test has to spell the cleanup out.
async fn with_toolchain_test_tree(
  body : async (@pathx.Absolute) -> Unit,
) -> Unit {
  let root = @pathx.Path(@fs.tmpdir(prefix="openseek-moonbit-external-")).resolve()
  defer remove_toolchain_test_tree(root)
  body(root)
}

///|
/// A complete fake toolchain: the resolver only assembles one around the
/// executable the desktop spawns — `moon`.
async fn touch_fake_toolchain(bin_dir : @pathx.Absolute) -> Unit {
  touch_fake_executable(bin_dir.join("moon" + ExecutableSuffix).to_path())
}

///|
#cfg(not(platform="windows"))
async test "a non-executable moon file does not count" {
  with_toolchain_test_tree(root => {
    let path_bin = root.join("pathdir")
    let home_bin = root.join("home").join(".moon").join("bin")
    @fs.mkdir(path_bin.to_string(), recursive=true)
    @fs.mkdir(home_bin.to_string(), recursive=true)
    @fs.write_text(
      path_bin.join("moon").to_string(),
      "",
      create_mode=CreateOrTruncate,
    )
    touch_fake_toolchain(home_bin)
    let toolchain = external_toolchain(
      path_env=path_bin.to_string(),
      home_dir=root.join("home").to_path(),
    )
    assert_eq(toolchain.bin_dir.to_string(), home_bin.to_string())
  })
}

///|
async test "a directory named moon does not count" {
  with_toolchain_test_tree(root => {
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
      home_dir=root.join("home").to_path(),
    )
    assert_eq(toolchain.bin_dir.to_string(), home_bin.to_string())
  })
}

///|
async test "an executable moon is a usable toolchain" {
  with_toolchain_test_tree(root => {
    let bin_dir = root.join("bin")
    @fs.mkdir(bin_dir.to_string(), recursive=true)
    @fs.write_text(
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
  with_toolchain_test_tree(root => {
    let not_a_dir = root.join("notdir")
    let home_bin = root.join("home").join(".moon").join("bin")
    @fs.write_text(not_a_dir.to_string(), "", create_mode=CreateOrTruncate)
    @fs.mkdir(home_bin.to_string(), recursive=true)
    touch_fake_toolchain(home_bin)
    let toolchain = external_toolchain(
      path_env=not_a_dir.to_string(),
      home_dir=root.join("home").to_path(),
    )
    assert_eq(toolchain.bin_dir.to_string(), home_bin.to_string())
  })
}

///|
async test "path scan wins over the default install" {
  with_toolchain_test_tree(root => {
    let home_bin = root.join("home").join(".moon").join("bin")
    let path_bin = root.join("pathdir")
    @fs.mkdir(home_bin.to_string(), recursive=true)
    @fs.mkdir(path_bin.to_string(), recursive=true)
    touch_fake_toolchain(home_bin)
    touch_fake_toolchain(path_bin)
    let toolchain = external_toolchain(
      path_env=path_bin.to_string(),
      home_dir=root.join("home").to_path(),
    )
    assert_eq(toolchain.bin_dir.to_string(), path_bin.to_string())
  })
}

///|
async test "no toolchain anywhere raises ToolchainUnavailable" {
  with_toolchain_test_tree(root => {
    let bare_bin = root.join("bare")
    @fs.mkdir(bare_bin.to_string(), recursive=true)
    try
      external_toolchain(
        path_env=bare_bin.to_string(),
        home_dir=root.join("home").to_path(),
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
  let bin_dir = @pathx.Path("found/bin").resolve()
  { bin_dir, moon: bin_dir.join("moon"), }.apply_to_env(env)
  assert_eq(env.get("MOON_HOME"), Some("/custom"))
  assert_true(
    env.get("PATH").map(path => path.has_prefix(bin_dir.to_string())) ==
    Some(true),
  )
}

///|
async test "explicit seed selection checks platform and fails without fallback" {
  async fn rejected(body : async () -> Unit) -> Unit {
    try body() catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid seed to be rejected")
    }
  }
  with_toolchain_test_tree(root => {
    let seed = root.join("seed with spaces")
    @fs.mkdir(seed.to_string(), recursive=true)
    @fs.write_text(
      seed.join(MoonbitSeedVersionFile).to_string(),
      "fixture",
      create_mode=CreateOrTruncate,
    )
    for
      pair in [
        ("linux-x64", "Linux-x86_64"),
        ("linux-arm64", "Linux-aarch64"),
        ("macos-arm64", "Darwin-arm64"),
      ] {
      let (platform, host_platform) = pair
      assert_true(
        bundled_source(platform~, host_platform~, seed_dir=seed.to_string())
        is Some(Bundled(_)),
      )
    }
    rejected(() => {
      ignore(
        bundled_source(
          platform="linux-arm64",
          host_platform="Linux-x86_64",
          seed_dir=seed.to_string(),
        ),
      )
    })
    rejected(() => {
      ignore(
        bundled_source(
          platform="linux-x64",
          host_platform="Linux-x86_64",
          seed_dir="relative",
        ),
      )
    })
    rejected(() => {
      ignore(
        bundled_source(
          platform="unsupported",
          host_platform="Linux-x86_64",
          seed_dir=seed.to_string(),
        ),
      )
    })
    guard bundled_source(
        platform="linux-x64",
        host_platform="Linux-x86_64",
        seed_dir=seed.to_string(),
      )
      is Some(selected) else {
      fail("test fixture seed marker is missing")
    }
    // No runtime means preparation cannot succeed. Never fall back to the
    // running test machine's otherwise available MoonBit installation.
    rejected(() => ignore(resolve_toolchain("unused", source=selected)))
    let marker = seed.join(MoonbitSeedVersionFile).to_string()
    @fs.remove(marker)
    assert_true(
      bundled_source(
        platform="linux-x64",
        host_platform="Linux-x86_64",
        seed_dir=seed.to_string(),
      )
      is None,
    )
    for content in ["", " \n\t"] {
      @fs.write_text(marker, content, create_mode=CreateOrTruncate)
      assert_true(
        bundled_source(
          platform="linux-x64",
          host_platform="Linux-x86_64",
          seed_dir=seed.to_string(),
        )
        is None,
      )
    }
    // A directory at the marker path is an I/O error, not a missing seed.
    @fs.remove(marker)
    @fs.mkdir(marker)
    rejected(() => {
      ignore(
        bundled_source(
          platform="linux-x64",
          host_platform="Linux-x86_64",
          seed_dir=seed.to_string(),
        ),
      )
    })
  })
}

///|
const FakeSeedVersion : String = "0.10.20+seed"

///|
/// Lay out a packaged engine beside a completed seed and return the engine
/// command. Preparing this seed would fail: its `moon` cannot bundle.
async fn fake_packaged_engine(root : @pathx.Absolute) -> String {
  let resources = root.join("seekmoon")
  let seed = resources.join("toolchains/moonbit/macos-arm64")
  @fs.mkdir(seed.join("bin").to_string(), recursive=true)
  @fs.write_text(
    seed.join(MoonbitSeedVersionFile).to_string(),
    FakeSeedVersion,
    create_mode=CreateOrTruncate,
  )
  resources.join("bin/openseek").to_string()
}

///|
/// A payload already prepared from the fake seed, so resolving to it reuses
/// it instead of running `moon bundle`. Returns its `bin` directory.
async fn fake_prepared_payload(runtime : @pathx.Absolute) -> String {
  let payload = runtime.join("toolchains/moonbit/macos-arm64").to_path()
  for
    file in [
      moonbit_command(payload),
      moonbit_compiler_command(payload),
      moonbit_native_bundle_probe_path(payload),
      moonbit_wasm_gc_bundle_probe_path(payload),
    ] {
    touch_fake_executable(file)
  }
  @fs.write_text(
    moonbit_bundle_stamp_path(payload).to_string(),
    "version=\{FakeSeedVersion}",
    create_mode=CreateOrTruncate,
  )
  moonbit_bin_dir(payload).to_string()
}

///|
async fn touch_fake_executable(path : @pathx.Path) -> Unit {
  @fsx.ensure_dir(path.dirname())
  @fs.write_text(
    path.to_string(),
    "",
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
}

///|
/// A user toolchain with `moon`, `moonx`, and a `moonc` reporting `version`.
async fn fake_user_toolchain(
  bin_dir : @pathx.Absolute,
  version~ : String,
) -> Unit {
  touch_fake_toolchain(bin_dir)
  touch_fake_executable(bin_dir.join("moonx").to_path())
  @fs.write_text(
    bin_dir.join("moonc").to_string(),
    "#!/bin/sh\nprintf '%s\\n' '\{version}'\n",
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
}

///|
test "compiler versions compare by release and ignore the build hash" {
  guard parse_compiler_version("v0.10.20+65efd5b93 (2026-11-05)\n")
    is Some(nightly) &&
    parse_compiler_version("0.10.20+b410defd5") is Some(stable) &&
    parse_compiler_version("v0.10.15+943464bfa (2026-10-12)") is Some(older) else {
    fail("well-formed compiler versions did not parse")
  }
  assert_eq(nightly.compare(stable), 0)
  assert_true(older.compare(stable) < 0)
  assert_true(parse_compiler_version("test-version") is None)
}

///|
#cfg(not(platform="windows"))
async test "a user toolchain no older than the seed wins" {
  with_toolchain_test_tree(root => {
    let engine = fake_packaged_engine(root)
    let user_bin = root.join("user/bin")
    fake_user_toolchain(user_bin, version="v0.10.20+user (2026-11-05)")
    let runtime = root.join("runtime")
    let toolchain = desktop_toolchain(
      engine,
      runtime_dir=runtime.to_path(),
      path_env=user_bin.to_string(),
      home_dir=root.join("home").to_path(),
    )
    assert_eq(toolchain.bin_dir.to_string(), user_bin.to_string())
    assert_false(@fsx.exists(runtime.join("toolchains").to_path()))
  })
}

///|
#cfg(not(platform="windows"))
async test "an older user toolchain falls back to the bundled seed" {
  with_toolchain_test_tree(root => {
    let engine = fake_packaged_engine(root)
    let user_bin = root.join("user/bin")
    fake_user_toolchain(user_bin, version="v0.10.15+old (2026-10-12)")
    let runtime = root.join("runtime")
    let payload_bin = fake_prepared_payload(runtime)
    let toolchain = desktop_toolchain(
      engine,
      runtime_dir=runtime.to_path(),
      path_env=user_bin.to_string(),
      home_dir=root.join("home").to_path(),
    )
    assert_eq(toolchain.bin_dir.to_string(), payload_bin)
  })
}

///|
async test "a user moon without moonx falls back to the bundled seed" {
  with_toolchain_test_tree(root => {
    let engine = fake_packaged_engine(root)
    let user_bin = root.join("user/bin")
    touch_fake_toolchain(user_bin)
    let runtime = root.join("runtime")
    let payload_bin = fake_prepared_payload(runtime)
    let toolchain = desktop_toolchain(
      engine,
      runtime_dir=runtime.to_path(),
      path_env=user_bin.to_string(),
      home_dir=root.join("home").to_path(),
    )
    assert_eq(toolchain.bin_dir.to_string(), payload_bin)
  })
}
