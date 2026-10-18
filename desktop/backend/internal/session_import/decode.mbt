///|
fn decode(text : String, imported : String) -> Array[Record] raise {
  guard @json.parse(text) is Object(dataset) &&
    dataset.get("/api/sessions") is Some(String(listing)) &&
    @json.parse(listing) is Array(rows) &&
    !rows.is_empty() else {
    raise SessionImportError(
      "Expected an OpenSeek conversation export JSON file.",
    )
  }
  let sessions : Array[Record] = []
  let keys : Map[String, Bool] = Map([])
  let mut original : String? = None
  let ids : Map[String, Bool] = Map([])
  for row in rows {
    guard row
      is {
        "key": String(key),
        "id": String(id),
        "first_prompt": String(prompt),
        ..
      } &&
      !key.is_empty() &&
      !keys.contains(key) &&
      dataset.get("/api/sessions/" + key) is Some(String(envelope)) &&
      @json.parse(envelope) is { "found": true, "events": String(events), .. } else {
      raise SessionImportError(
        "The export contains a missing or invalid session record.",
      )
    }
    keys[key] = true
    let parsed = @log.parse_events(events)
    guard parsed.header is Some(header) &&
      parsed.errors.is_empty() &&
      !parsed.partial_tail else {
      raise SessionImportError(
        "The export contains an unsupported, damaged or incomplete session log.",
      )
    }
    for index, event in parsed.events {
      guard event.sequence() == index + 1 else {
        raise SessionImportError("Session event sequences must be contiguous.")
      }
    }
    if original is None {
      original = Some(id)
    }
    let parent = original.unwrap()
    guard !ids.contains(id) && (id == parent || id.has_prefix(parent + "-sr-")) else {
      raise SessionImportError("Expected one conversation and its subruns.")
    }
    ids[id] = true
    let suffix = id.view(start_offset=parent.length()).to_owned()
    guard suffix
      .iter()
      .all(c => c.is_ascii_digit() || c == '-' || c == 's' || c == 'r') else {
      raise SessionImportError("Invalid subrun session id.")
    }
    let local_id = imported + suffix
    let session = @log.session_from_parse(
      parsed,
      id=local_id,
      system_prompt=header.system_prompt,
    )
    sessions.push({
      title: if prompt.is_blank() {
        "Imported conversation"
      } else {
        prompt
      },
      session,
    })
  }
  sessions
}
