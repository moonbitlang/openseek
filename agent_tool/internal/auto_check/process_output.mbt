///|
/// Bounded merged stdout/stderr from a compiler process. An output-limit kill
/// has no exit code; an ordinary failure retains the process's non-zero code.
priv struct ProcessOutput {
  exit_code : Int?
  text : String
  output_limit_reached : Bool
}

///|
/// Run a compiler directly with literal arguments and immediately-closed stdin.
/// The owning task group cancels the child on timeout, read failure, or output
/// overflow; callers supply the wall-clock bound around this collection.
async fn collect_process_output(
  program : String,
  args : Array[String],
  cwd~ : String,
  max_output_chars~ : Int,
) -> ProcessOutput {
  let (reader, writer) = @process.read_from_process()
  @async.with_task_group() <| group => {
    defer reader.close()
    let (stdin_reader, stdin_writer) = @process.write_to_process()
    stdin_writer.close()
    let process = @process.spawn(
      group,
      program,
      args,
      stdin=stdin_reader,
      stdout=writer,
      stderr=writer,
      cwd=cwd.view(),
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
async fn read_output_prefix(
  reader : @process.ReadFromProcess,
  max_output_chars : Int,
) -> OutputPrefix {
  let buffer = Buffer()
  let byte_budget = max_output_chars * 4 + 4
  for ;; {
    let remaining_budget = byte_budget - buffer.length()
    let chunk_limit = remaining_budget.clamp(min=1, max=1024)
    match reader.read_some(max_len=chunk_limit) {
      None =>
        return {
          text: decode_valid_utf8_prefix(buffer.to_bytes()),
          output_limit_reached: false,
        }
      Some(chunk) => {
        buffer.write_bytes(chunk)
        let text = decode_valid_utf8_prefix(buffer.to_bytes())
        if text.char_length() > max_output_chars {
          return {
            text: text_prefix_by_chars(text, max_output_chars),
            output_limit_reached: true,
          }
        } else {
          continue
        }
      }
    }
  }
}

///|
fn text_prefix_by_chars(text : String, max_chars : Int) -> String {
  match text.offset_of_nth_char(max_chars) {
    Some(end) => "\{text[:end]}"
    None => text
  }
}

///|
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
