// Running a user-typed `!` command for a client that offers shell mode (the
// terminal UI, the desktop app). The result is the shared
// `@command_context.ShellOutput`, which the client wraps in the
// `<user_shell_command>` envelope and hands the engine as command context.

///|
/// The character budget a `!` command's captured output is cut to.
let default_max_output_chars : Int = 12000

///|
/// Run `cmd` through the platform shell (`sh -c`, or `powershell.exe` on
/// Windows) in `cwd`, capturing merged stdout+stderr up to `max_output_chars`.
/// It applies no command policy: clients run only commands the user typed
/// after `!`. Reaching the cap stops the command, and its exit code is then
/// `None`. The child gets a closed stdin, so a command that reads input sees
/// EOF instead of hanging. `env`, when given, is the child's complete
/// environment; otherwise it inherits this process's.
pub async fn collect_shell_output(
  cmd : String,
  cwd? : String,
  env? : Map[String, String],
  max_output_chars? : Int = default_max_output_chars,
) -> @command_context.ShellOutput {
  let (reader, writer) = @process.read_from_process()
  @async.with_task_group() <| group => {
    defer reader.close()
    // A closed stdin pipe keeps the Windows spawn from falling back to a NULL
    // console handle.
    let (stdin_reader, stdin_writer) = @process.write_to_process()
    stdin_writer.close()
    let process = @process.spawn(
      group,
      @platform_shell.program,
      @platform_shell.args(cmd),
      extra_env?=env,
      inherit_env=env is None,
      stdin=stdin_reader,
      stdout=writer,
      stderr=writer,
      cwd?=cwd.map(cwd => cwd.view()),
      cancel_handler=@process.hard_cancel(),
      no_wait=true,
      no_console_window=true,
    )
    let prefix = read_output_prefix(reader, max_output_chars)
    let exit_code = if prefix.output_limit_reached {
      None
    } else {
      Some(process.wait())
    }
    {
      exit_code,
      text: prefix.text,
      output_limit_reached: prefix.output_limit_reached,
    }
  }
}

///|
priv struct OutputPrefix {
  text : String
  output_limit_reached : Bool
}

///|
/// Read merged output until EOF or until it exceeds `max_output_chars`,
/// returning at most that many characters.
async fn read_output_prefix(
  reader : @process.ReadFromProcess,
  max_output_chars : Int,
) -> OutputPrefix {
  let buffer = Buffer()
  let byte_budget = max_output_chars * 4 + 4
  for ;; {
    let chunk_limit = (byte_budget - buffer.length()).clamp(min=1, max=1024)
    guard reader.read_some(max_len=chunk_limit) is Some(chunk) else {
      return {
        text: decode_valid_utf8_prefix(buffer.to_bytes()),
        output_limit_reached: false,
      }
    }
    buffer.write_bytes(chunk)
    let text = decode_valid_utf8_prefix(buffer.to_bytes())
    if text.offset_of_nth_char(max_output_chars) is Some(end) {
      return { text: text[:end].to_owned(), output_limit_reached: true, }
    }
  }
}

///|
/// Decode `bytes` as UTF-8, dropping up to three trailing bytes of a character
/// the read cut in half; anything else invalid decodes lossily.
fn decode_valid_utf8_prefix(bytes : Bytes) -> String {
  for dropped in 0..<=3 {
    let end = bytes.length() - dropped
    if end >= 0 {
      try {
        return @utf8.decode(bytes[:end])
      } catch {
        _ => ()
      }
    }
  }
  @utf8.decode_lossy(bytes)
}
