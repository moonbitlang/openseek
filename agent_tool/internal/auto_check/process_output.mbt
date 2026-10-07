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
/// Read the child's output until it ends or exceeds `max_output_chars`. The
/// bytes are decoded as they arrive, so a capture costs time linear in its
/// size; the bytes of a character split across two reads wait in `pending`.
async fn read_output_prefix(
  reader : @process.ReadFromProcess,
  max_output_chars : Int,
) -> OutputPrefix {
  let text = StringBuilder()
  let mut chars = 0
  let mut bytes_read = 0
  let mut pending : Bytes = b""
  let byte_budget = max_output_chars * 4 + 4
  for ;; {
    let chunk_limit = (byte_budget - bytes_read).clamp(min=1, max=1024)
    // A character left incomplete when the stream ends is dropped.
    guard reader.read_some(max_len=chunk_limit) is Some(chunk) else {
      return { text: text.to_string(), output_limit_reached: false, }
    }
    bytes_read += chunk.length()
    let (decoded, rest) = decode_complete_chars(pending + chunk)
    pending = rest
    text.write_string(decoded)
    chars += decoded.char_length()
    if chars > max_output_chars {
      return {
        text: text_prefix_by_chars(text.to_string(), max_output_chars),
        output_limit_reached: true,
      }
    }
  }
}

///|
fn text_prefix_by_chars(text : String, max_chars : Int) -> String {
  text.offset_of_nth_char(max_chars).map_or(text, end => "\{text[:end]}")
}

///|
/// Decode `bytes` up to its last complete character, returning the at most
/// three trailing bytes that begin a character and wait for its rest. Where
/// to cut is read off the bytes themselves, so malformed bytes earlier in the
/// input (decoded lossily) do not cost the split character after them.
fn decode_complete_chars(bytes : Bytes) -> (String, Bytes) {
  let end = bytes.length() - incomplete_tail_length(bytes)
  let complete = bytes[:end]
  let text = @utf8.decode(complete) catch { _ => @utf8.decode_lossy(complete) }
  (text, bytes[end:].to_owned())
}

///|
/// How many bytes at the end of `bytes` are a lead byte and continuation
/// bytes short of the length that lead announces; 0 when the input ends on a
/// character boundary, or on bytes no later byte could complete.
fn incomplete_tail_length(bytes : Bytes) -> Int {
  let length = bytes.length()
  for back in 1..<=3 {
    if back > length {
      break
    }
    let byte = bytes[length - back].to_int()
    // A continuation byte: the lead is further back.
    if byte is (0x80..=0xBF) {
      continue
    }
    let announced = match byte {
      0xC0..=0xDF => 2
      0xE0..=0xEF => 3
      0xF0..=0xF7 => 4
      _ => 1
    }
    return if announced > back { back } else { 0 }
  }
  0
}
