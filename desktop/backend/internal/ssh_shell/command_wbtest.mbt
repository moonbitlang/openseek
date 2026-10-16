///|
#cfg(not(platform="windows"))
async test "login shells preserve environment quoted payload and binary stdin" {
  let root = @fs.tmpdir(prefix="ssh-login-")
  defer @fs.rmdir(root, recursive=true)
  let input = root + "/input"
  @fs.write_file(input, b"\x00\xff\n")
  for
    shell in [
      "/bin/sh", "/bin/bash", "/bin/zsh", "/bin/csh", "/bin/tcsh", "/opt/homebrew/bin/fish",
    ] {
    if !@fs.exists(shell) {
      continue
    }
    let home = root + "/" + shell.replace_all(old="/", new="_")
    @fs.mkdir(home + "/.config/fish", recursive=true)
    for rc in [".profile", ".bash_profile", ".zprofile"] {
      @fs.write_file(
        home + "/" + rc,
        "export SSH_QA_LOGIN=loaded\nprintf 'banner'\n",
      )
    }
    @fs.write_file(
      home + "/.login",
      "setenv SSH_QA_LOGIN loaded\necho banner\n",
    )
    @fs.write_file(
      home + "/.config/fish/config.fish",
      "set -gx SSH_QA_LOGIN loaded\necho banner\n",
    )
    let payload = "printf '__READY__%s\\n' \"$SSH_QA_LOGIN\"; printf '%s\\n' \"quote ' dollar \\$HOME 中文\"; exec cat\n"
    let (status, stdout, stderr) = @async.with_timeout(5000, () => {
      @process.collect_output(
        shell,
        ["-c", command(payload)],
        extra_env={
          "HOME": home,
          "ZDOTDIR": home,
          "XDG_CONFIG_HOME": home + "/.config",
          "SHELL": shell,
        },
        stdin=@process.redirect_from_file(input),
      )
    })
    assert_eq(status, 0, msg=stderr.text())
    let expected = @utf8.encode(
        "__READY__loaded\nquote ' dollar $HOME 中文\n",
      ) +
      b"\x00\xff\n"
    assert_true(stdout.binary().has_suffix(expected))
  }
}
