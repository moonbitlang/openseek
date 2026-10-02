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
    // Output is drained beside the exit wait rather than before it: a
    // descendant the command left running (`server &`) inherits the pipe and
    // can hold it open long after the shell itself has exited.
    let output = OutputPrefix::new(max_output_chars)
    let draining = group.spawn(() => {
      // A read failure ends the drain with what was read so far.
      output.drain(reader) catch {
        _ => ()
      }
      output.drained = true
      if output.output_limit_reached {
        process.cancel()
      }
    })
    let exit_code = process.wait() catch { _ => -1 }
    // The shell is gone, but the pipe may still hold what it wrote just before
    // exiting. Let the reader reach EOF; if it is still blocked after a short
    // grace, a descendant is holding the pipe open, and what was read is the
    // result.
    ignore(
      @async.with_timeout_opt(drain_grace_ms, () => {
        while !output.drained {
          @async.sleep(5)
        }
      }),
    )
    draining.cancel()
    {
      exit_code: if output.output_limit_reached {
        None
      } else {
        Some(exit_code)
      },
      text: output.text,
      output_limit_reached: output.output_limit_reached,
    }
  }
}

///|
/// How long the reader may keep draining after the shell exits before a pipe
/// still held open by a descendant is closed.
let drain_grace_ms : Int = 200

///|
/// The captured prefix of a command's merged output, filled by `drain`.
priv struct OutputPrefix {
  max_output_chars : Int
  buffer : Buffer
  mut text : String
  mut output_limit_reached : Bool
  mut drained : Bool
}

///|
fn OutputPrefix::new(max_output_chars : Int) -> OutputPrefix {
  {
    max_output_chars,
    buffer: Buffer(),
    text: "",
    output_limit_reached: false,
    drained: false,
  }
}

///|
/// Read merged output until EOF or until it exceeds `max_output_chars`,
/// keeping at most that many characters in `text`.
async fn OutputPrefix::drain(
  self : OutputPrefix,
  reader : @process.ReadFromProcess,
) -> Unit {
  let byte_budget = self.max_output_chars * 4 + 4
  for ;; {
    let chunk_limit = (byte_budget - self.buffer.length()).clamp(
      min=1,
      max=1024,
    )
    guard reader.read_some(max_len=chunk_limit) is Some(chunk) else { return }
    self.buffer.write_bytes(chunk)
    let text = decode_valid_utf8_prefix(self.buffer.to_bytes())
    if text.offset_of_nth_char(self.max_output_chars) is Some(end) {
      self.text = text[:end].to_owned()
      self.output_limit_reached = true
      return
    }
    self.text = text
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
