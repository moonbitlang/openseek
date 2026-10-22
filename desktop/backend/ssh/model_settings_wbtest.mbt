///|
async test "SSH bootstrap preserves its startup pipe and passes provider credentials literally" {
  if @async.platform is Windows {
    return
  }
  let directory = @fs.tmpdir(prefix="ssh-model-settings-")
  defer @fs.rmdir(directory, recursive=true)
  let home = directory + "/home with spaces"
  let prepared = home + "/.openseek/ssh/v" + CliRelease
  @fs.mkdir(prepared + "/bin", recursive=true)
  @fs.write_file(prepared + "/.prepared", "")
  @fs.write_file(
    prepared + "/bin/openseek",
    "#!/bin/sh\nexit 0\n",
    permission=0o755,
  )
  let server = prepared + "/bin/openseek-app-server"
  @fs.write_file(
    server,
    "#!/bin/sh\n[ \"$#\" -eq 0 ] || exit 23\n[ -p /dev/fd/0 ] || exit 24\nprintf '%s\\n' \"$DEEPSEEK\" \"$KIMI\" \"$GLM\" > \"$HOME/captured\"\nprintf '%s\\n' '{\"port\":1234}'\ncat >/dev/null\ntouch \"$HOME/closed\"\n",
    permission=0o755,
  )
  let values : Map[String, String] = {
    "DEEPSEEK": "secret-'\\\"中文-$(touch " + directory + "/executed)-`false`",
  }
  let line = model_environment_input(values)
  let command = remote_command(model_environment=true)
  assert_false(command.contains("secret-"))
  let expected = values["DEEPSEEK"] + "\nremote-kimi\nremote-glm\n"
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let (input, writer) = @process.write_to_process()
      defer writer.close()
      let (reader, output) = @process.read_from_process()
      defer reader.close()
      let child = @process.spawn(
        group,
        "sh",
        ["-c", command],
        stdin=input,
        stdout=output,
        inherit_env=false,
        extra_env={
          "HOME": home,
          "PATH": "/usr/bin:/bin",
          "DEEPSEEK": "remote-deepseek",
          "KIMI": "remote-kimi",
          "GLM": "remote-glm",
        },
      )
      writer.write(line)
      assert_eq(reader.read_until("\n"), Some("{\"stage\":\"connecting\"}"))
      assert_eq(reader.read_until("\n"), Some("{\"port\":1234}"))
      assert_eq(@fs.read_file(home + "/captured").text(), expected)
      assert_true(child.try_wait() is None)
      writer.close()
      assert_eq(child.wait(), 0)
      while !@fs.exists(home + "/closed") {
        @async.sleep(10)
      }
    })
  })
  assert_false(@fs.exists(directory + "/executed"))
}

///|
test "SSH rejects multiline model values before opening the connection" {
  for name in model_environment_names {
    for value in ["first\nsecond", "first\rsecond", "first\u0000second"] {
      assert_true(
        try {
          ignore(model_environment_input(Map([(name, value)])))
          false
        } catch {
          SshError(_) => true
        },
      )
    }
  }
}
