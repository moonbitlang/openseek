///|
async test "SSH bootstrap passes a provider key literally and preserves other remote credentials" {
  if @async.platform is Windows {
    return
  }
  let directory = @fs.tmpdir(prefix="ssh-model-settings-")
  defer @fs.rmdir(directory, recursive=true)
  let server = directory + "/server with spaces"
  @fs.write_file(
    server,
    "#!/bin/sh\n[ \"$#\" -eq 0 ] || exit 23\nprintf '%s\\n' \"$DEEPSEEK\" \"$KIMI\" \"$GLM\"\ncat >/dev/null\nprintf 'closed\\n'\n",
    permission=0o755,
  )
  let values : Map[String, String] = {
    "DEEPSEEK": "secret-'\\\"中文-$(touch " + directory + "/executed)-`false`",
  }
  let line = model_environment_input(values)
  let command = remote_command(server, model_environment=true)
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
          "PATH": "/usr/bin:/bin",
          "DEEPSEEK": "remote-deepseek",
          "KIMI": "remote-kimi",
          "GLM": "remote-glm",
        },
      )
      writer.write(line)
      assert_eq(
        @utf8.decode(reader.read_exactly(@utf8.encode(expected).length())),
        expected,
      )
      assert_true(child.try_wait() is None)
      writer.close()
      assert_eq(reader.read_exactly(7), b"closed\n")
      assert_eq(child.wait(), 0)
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
