///|
async fn executable(path : String, text : String) -> Unit {
  @fs.write_file(path, "#!/bin/sh\nprintf '\{text}\\n'\n", permission=0o755)
}

///|
async fn fixture_toolchain(destination : String) -> Unit {
  @fs.mkdir(destination + "/bin", recursive=true, allow_exist=true)
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
  for
    file in [
      "doc/moonbit/index.md", "doc/moonbit/language/index.md", "doc/moonbit/language/fundamentals.md",
      "doc/moonbit/toolchain/index.md", "workflow/read.mbtx",
    ] {
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
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  install(
    home,
    source_cli,
    available=isolated_available,
    toolchain=fixture_toolchain,
  )
  assert_true(usable(home + "/.moon/bin/moon", ["version"]))
  assert_true(usable(home + "/.openseek/bin/openseek", ["--help"]))
  assert_true(usable(home + "/.openseek/bin/rg", ["--version"]))
  assert_eq(
    @fs.read_file(home + "/.openseek/share/licenses/LICENSE").text(),
    "fixture license",
  )
  @fs.rmdir(home + "/download", recursive=true)
  install(
    home,
    home + "/.openseek/bin/openseek",
    available=isolated_available,
    toolchain=_ => fail("must not reinstall SDK"),
  )
  assert_eq(command(home + "/.openseek/bin/rg", ["--version"]), "fixture-rg\n")
  assert_eq(
    @fs.read_file(
      home + "/.openseek/share/doc/moonbit/language/fundamentals.md",
    ).text(),
    "resource",
  )
  assert_eq(
    @fs.read_file(home + "/.openseek/share/licenses/LICENSE").text(),
    "fixture license",
  )
}

///|
async test "setup resolves a launcher symlink outside the extracted distribution" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  let launcher = home + "/launchers/openseek"
  @fs.mkdir(home + "/launchers")
  @fs.symlink(target=source_cli, launcher)
  install(
    home,
    launcher,
    available=isolated_available,
    toolchain=fixture_toolchain,
  )
  assert_eq(
    command(home + "/.openseek/bin/openseek", ["--help"]),
    "bootstrap-cli\n",
  )
  assert_eq(command(home + "/.openseek/bin/rg", ["--version"]), "fixture-rg\n")
  assert_eq(
    @fs.read_file(home + "/.openseek/share/doc/moonbit/index.md").text(),
    "resource",
  )
}

///|
async test "setup reuses PATH MoonBit but replaces rg and the complete resource tree" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  fixture_bundle(home + "/.openseek")
  @fs.write_file(
    home + "/.openseek/share/doc/moonbit/index.md",
    "old documentation",
  )
  @fs.write_file(home + "/.openseek/share/doc/moonbit/obsolete.md", "old")
  @fs.remove(home + "/.openseek/share/doc/moonbit/language/fundamentals.md")
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
  )
  assert_false(@fs.exists(home + "/.moon"))
  assert_eq(command(home + "/.openseek/bin/rg", ["--version"]), "fixture-rg\n")
  assert_eq(
    command(home + "/.openseek/bin/openseek", ["--help"]),
    "bootstrap-cli\n",
  )
  assert_eq(
    @fs.read_file(home + "/.openseek/share/doc/moonbit/index.md").text(),
    "resource",
  )
  assert_false(@fs.exists(home + "/.openseek/share/doc/moonbit/obsolete.md"))
  assert_eq(
    @fs.read_file(
      home + "/.openseek/share/doc/moonbit/language/fundamentals.md",
    ).text(),
    "resource",
  )
}

///|
async test "setup replaces working rg without replacing MoonBit or CLI" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  fixture_toolchain(home + "/.moon")
  fixture_bundle(home + "/.openseek")
  executable(home + "/.openseek/bin/openseek", "keep-cli")
  executable(home + "/.openseek/bin/rg", "old-rg")
  @fs.write_file(home + "/.moon/credentials", "keep")
  install(home, source_cli, available=isolated_available, toolchain=_ => {
    fail("SDK must not be replaced")
  })
  assert_eq(command(home + "/.openseek/bin/rg", ["--version"]), "fixture-rg\n")
  assert_eq(command(home + "/.openseek/bin/openseek", ["--help"]), "keep-cli\n")
  assert_eq(@fs.read_file(home + "/.moon/credentials").text(), "keep")
}

///|
async test "setup propagates installer failure and trusts successful return" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  let available : async (String, Array[String]) -> Bool = (program, args) => {
    if program.has_suffix("/openseek") {
      isolated_available(program, args)
    } else {
      false
    }
  }
  let error = try {
    install(home, source_cli, available~, toolchain=destination => {
      @fs.mkdir(destination, recursive=true)
      @fs.write_file(destination + "/credentials", "keep")
      fail("installer failed")
    })
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(error.contains("installer failed"))
  install(home, source_cli, available~, toolchain=fixture_toolchain)
  assert_true(usable(home + "/.openseek/bin/openseek", ["--help"]))
  assert_eq(@fs.read_file(home + "/.moon/credentials").text(), "keep")
}

///|
async test "concurrent setup checks installed files again after taking the lock" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  let installations = Ref(0)
  let setup : async () -> Unit = () => {
    install(home, source_cli, available=isolated_available, toolchain=destination => {
      installations.val += 1
      fixture_toolchain(destination)
    })
  }
  @async.with_task_group(group => {
    let first = group.spawn(setup)
    let second = group.spawn(setup)
    first.wait()
    second.wait()
  })
  assert_eq(installations.val, 1)
}

///|
async test "a missing resource source fails before installing MoonBit or deleting resources" {
  if @async.platform is Windows {
    return
  }
  let home = @fs.tmpdir(prefix="openseek-setup-test-")
  defer @fs.rmdir(home, recursive=true)
  let source_cli = fixture_distribution(home)
  fixture_bundle(home + "/.openseek")
  @fs.rmdir(home + "/download/share", recursive=true)
  let error = try {
    install(home, source_cli, available=isolated_available, toolchain=_ => {
      fail("must validate the archive before installing MoonBit")
    })
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(error.contains(home + "/download/share"))
  assert_false(@fs.exists(home + "/.moon"))
  assert_eq(
    @fs.read_file(home + "/.openseek/share/licenses/LICENSE").text(),
    "fixture license",
  )
}
