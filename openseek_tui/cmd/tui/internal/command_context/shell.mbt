///|
/// The character budget a `!` command's captured output is cut to.
let default_max_output_chars : Int32 = 12000

///|
/// The result of running a shell command line: the `exit_code` (`None` if the
/// command was cut off at the output cap before it exited), the merged
/// stdout+stderr `text` (truncated to the character budget), and whether that
/// truncation happened.
pub(all) struct ShellOutput {
  exit_code : Int32?
  text : String
  output_limit_reached : Bool
}

///|
/// The platform shell that interprets command text: `powershell.exe` on
/// Windows — always installed, unlike `pwsh` — and `sh` elsewhere. Select at
/// runtime so a wasm build follows the host running it.
let shell_program : String = match @async.platform {
  Windows => "powershell.exe"
  Linux | MacOS => "sh"
}

///|
/// Arguments that make `shell_program` run `cmd` as shell text. PowerShell is
/// switched to UTF-8 output so non-ASCII text arrives as valid UTF-8 rather
/// than the active code page.
fn shell_args(cmd : String) -> Array[String] {
  match @async.platform {
    Windows =>
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "$OutputEncoding=[Console]::OutputEncoding=[Text.Encoding]::UTF8;chcp 65001 > $null;" +
        cmd,
      ]
    Linux | MacOS => ["-c", cmd]
  }
}

///|
/// Run `cmd` through the platform shell (`sh -c`, or `powershell.exe` on
/// Windows), capturing merged stdout+stderr up to `max_output_chars`. It
/// applies no command policy: the TUI runs only commands the user typed after
/// `!`. Reaching the cap stops the command, and its exit code is then `None`.
pub async fn collect_shell_output(
  cmd : String,
  cwd? : String,
  max_output_chars~ : Int32 = default_max_output_chars,
) -> ShellOutput {
  let (reader, writer) = @process.read_from_process()
  @async.with_task_group() <| group => {
    defer reader.close()
    // A closed stdin pipe keeps the Windows spawn from falling back to a NULL
    // console handle.
    let (stdin_reader, stdin_writer) = @process.write_to_process()
    stdin_writer.close()
    let process = @process.spawn(
      group,
      shell_program,
      shell_args(cmd),
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
  max_output_chars : Int32,
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
