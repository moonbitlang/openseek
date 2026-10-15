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
  @fs.mkdir(destination + "/share/licenses", allow_exist=true)
  @fs.write_file(destination + "/share/licenses/LICENSE", "fixture license")
}

///|
async fn fixture_distribution(home : String) -> String {
  let directory = home + "/download"
  fixture_bundle(directory)
  let cli = directory + "/bin/openseek"
  executable(cli, "bootstrap-cli")
  cli
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
  let source_cli = fixture_distribution(home)
  assert_false(
    install(
      home,
      source_cli,
      available=isolated_available,
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
  @fs.rmdir(home + "/download", recursive=true)
  assert_true(
    install(home, source_cli, available=isolated_available, toolchain=_ => {
      fail("must not reinstall SDK")
    }),
  )
}

///|
async test "setup reuses PATH tools and preserves existing resource files" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  @fs.mkdir(home + "/.openseek/share/doc/moonbit", recursive=true)
  @fs.write_file(
    home + "/.openseek/share/doc/moonbit/index.md",
    "user documentation",
  )
  assert_false(
    install(
      home,
      source_cli,
      available=(program, args) => {
        if ["moon", "moonc", "moonrun", "moonx", "rg"].contains(program) {
          true
        } else {
          isolated_available(program, args)
        }
      },
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
  let source_cli = fixture_distribution(home)
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
    install(home, source_cli, available=isolated_available, toolchain=_ => {
      fail("SDK must not be replaced")
    }),
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
async test "failed SDK installation remains retryable without a completion stamp" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  let error = try {
    install(home, source_cli, available=isolated_available, toolchain=destination => {
      fixture_toolchain(destination)
      @fs.rmdir(destination + "/lib/core", recursive=true)
      @fs.write_file(destination + "/credentials", "keep")
      fail("installer failed")
    })
    |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(error.contains("installer failed"))
  assert_false(
    install(
      home,
      source_cli,
      available=isolated_available,
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
  let source_cli = fixture_distribution(home)
  let installations = Ref(0)
  let setup : async () -> Bool = () => {
    install(home, source_cli, available=isolated_available, toolchain=destination => {
      installations.val += 1
      fixture_toolchain(destination)
    })
  }
  @async.with_task_group(group => {
    let first = group.spawn(setup)
    let second = group.spawn(setup)
    assert_true(first.wait() != second.wait())
  })
  assert_eq(installations.val, 1)
}

///|
async test "an incomplete extracted distribution fails before installing MoonBit" {
  if is_windows() {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  @fs.rmdir(home + "/download/share", recursive=true)
  let error = try {
    install(home, source_cli, available=isolated_available, toolchain=_ => {
      fail("must validate the archive before installing MoonBit")
    })
    |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(error.contains("missing share"))
  assert_false(@fs.exists(home + "/.moon"))
}
