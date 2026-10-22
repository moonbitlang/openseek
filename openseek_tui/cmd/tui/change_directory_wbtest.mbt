///|
async test "-C re-roots the workspace and relative flag paths" {
  @vfs.with_tmpdir(prefix="openseek-tui-chdir-", root => {
    let dir = @fs.realpath(root)
    let parsed = cli_command().parse(
      argv=["-C", root, "--engine", "bin/openseek"],
      env={ "DEEPSEEK": "test-key" },
    )
    guard parsed is { values: { "change-directory": [given], .. }, .. } else {
      fail("-C not parsed as --change-directory")
    }
    let config = in_directory(parse_config(parsed), given)
    assert_eq(config.cwd, dir)
    assert_eq(config.session_root, "\{dir}/.openseek")
    assert_eq(config.engine, "\{dir}/bin/openseek")
    assert_true(config.engine_serve_args().contains("--dir=\{dir}"))
    // Absolute paths and a bare PATH command are left alone.
    let parsed = cli_command().parse(
      argv=["--session-root", "/var/sessions", "--engine", "openseek"],
      env={ "DEEPSEEK": "test-key" },
    )
    let config = in_directory(parse_config(parsed), root)
    assert_eq(config.session_root, "/var/sessions")
    assert_eq(config.engine, "openseek")
  })
}

///|
async test "-C rejects a missing directory and a file" {
  @vfs.with_tmpdir(prefix="openseek-tui-chdir-", root => {
    let config = parse_config(
      cli_command().parse(argv=[], env={ "DEEPSEEK": "test-key" }),
    )
    let missing = "\{root}/missing"
    let _ = in_directory(config, missing) catch {
      Failure(message) => {
        assert_true(message.contains("cannot change directory to \{missing}"))
        let file = "\{root}/file"
        @fs.write_file(file, "")
        let _ = in_directory(config, file) catch {
          Failure(message) => {
            assert_true(
              message.has_suffix(
                "cannot change directory to \{file}: not a directory",
              ),
            )
            return
          }
          error => raise error
        }
        fail("-C accepted a file")
      }
      error => raise error
    }
    fail("-C accepted a missing directory")
  })
}

///|
async test "-C then --continue resumes the latest session under the new directory" {
  @vfs.with_tmpdir(prefix="openseek-tui-chdir-continue-", root => {
    let dir = @fs.realpath(root)
    @store.SessionStore("\{dir}/.openseek").create(
      Session(SessionId("in-dir"), system_prompt="system"),
    )
    let parsed = cli_command().parse(argv=["--continue", "-C", root], env={
      "DEEPSEEK": "test-key",
    })
    // `run`'s order: re-root first, so --continue reads the -C store.
    let config = with_latest_session(in_directory(parse_config(parsed), root))
    assert_eq(config.session_root, "\{dir}/.openseek")
    assert_eq(config.session_id.value(), "in-dir")
  })
}
