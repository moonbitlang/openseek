///|
async test "a prompt file is refused when the session already exists" {
  @vfs.with_tmpdir(prefix="openseek-tui-prompt-", root => {
    @store.SessionStore(root).create(
      Session(SessionId("existing"), system_prompt="stored"),
    )
    let parsed = cli_command().parse(
      argv=[
        "--session", "existing", "--session-root", root, "--system-prompt-file",
        "base.md",
      ],
      env={ "DEEPSEEK": "test-key" },
    )
    let _ = reject_prompt_for_existing_session(parse_config(parsed)) catch {
      Failure(message) => {
        assert_true(message.contains("--system-prompt-file"))
        assert_true(message.contains("session existing already exists"))
        assert_true(message.contains("sessions fork existing"))
        return
      }
      error => raise error
    }
    fail("a prompt file was accepted for an existing session")
  })
}

///|
async test "a prompt file is accepted for a session this launch creates" {
  @vfs.with_tmpdir(prefix="openseek-tui-prompt-fresh-", root => {
    let parsed = cli_command().parse(
      argv=[
        "--session", "fresh", "--session-root", root, "--system-prompt-addendum-file",
        "extra.md",
      ],
      env={ "DEEPSEEK": "test-key" },
    )
    reject_prompt_for_existing_session(parse_config(parsed)) catch {
      error => fail("a fresh session refused its prompt files: \{error}")
    }
  })
}

///|
async test "--continue refuses prompt files once a session exists" {
  @vfs.with_tmpdir(prefix="openseek-tui-prompt-continue-", root => {
    @store.SessionStore(root).create(
      Session(SessionId("latest"), system_prompt="stored"),
    )
    let parsed = cli_command().parse(
      argv=[
        "--continue", "--session-root", root, "--system-prompt-file", "base.md",
      ],
      env={ "DEEPSEEK": "test-key" },
    )
    let config = with_latest_session(parse_config(parsed))
    assert_eq(config.session_id.value(), "latest")
    let _ = reject_prompt_for_existing_session(config) catch {
      Failure(message) => {
        assert_true(message.contains("already exists"))
        return
      }
      error => raise error
    }
    fail("--continue accepted a prompt file for an existing session")
  })
}
