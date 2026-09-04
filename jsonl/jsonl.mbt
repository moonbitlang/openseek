///|
/// Returns `true` when `line` holds only JSON-insignificant whitespace and so
/// carries no value to decode.
fn is_blank(line : String) -> Bool {
  for ch in line {
    if ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n' {
      return false
    }
  }
  true
}

///|
/// Parses one JSON Lines entry. A blank line yields `None`; any other line is
/// decoded as a single JSON value and raises when it is not valid JSON.
fn parse_line(line : String) -> Json? raise {
  if is_blank(line) {
    None
  } else {
    Some(@json.parse(line))
  }
}

///|
/// Parses newline-delimited JSON text into an array of values, skipping blank
/// lines and raising on the first malformed line.
///
/// This pure helper performs no IO, which makes it convenient for input that is
/// already buffered and for tests.
pub fn parse(text : String) -> Array[Json] raise {
  let values = []
  for line in text.split("\n") {
    if parse_line(line.to_owned()) is Some(value) {
      values.push(value)
    }
  }
  values
}

///|
/// Streams newline-delimited JSON values from `reader`, invoking `visit` on each
/// parsed value in order. Blank lines are skipped. Raises on a malformed line or
/// on a read error.
pub async fn[R : @io.Reader] each(
  reader : R,
  visit : (Json) -> Unit raise,
) -> Unit {
  while true {
    match reader.read_until("\n") {
      None => break
      Some(line) => if parse_line(line) is Some(value) { visit(value) }
    }
  }
}

///|
/// Reads every newline-delimited JSON value from `reader` into an array.
pub async fn[R : @io.Reader] read_all(reader : R) -> Array[Json] {
  let values = []
  each(reader, value => values.push(value))
  values
}

///|
/// Reads every newline-delimited JSON value from standard input into an array.
///
/// This is a convenience over [read_all] for the common case of consuming a
/// program's JSONL output from a pipe, so the caller need not import
/// `moonbitlang/async/stdio` itself.
pub async fn read_stdin() -> Array[Json] {
  read_all(@stdio.stdin)
}
