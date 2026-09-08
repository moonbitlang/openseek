// Explicit codecs for the Desktop semantic-search boundary. Unknown fields
// are ignored for forward evolution; every consumed field deliberately
// specifies missing, null, malformed, and encoded behavior. The wire shapes
// mirror the text-search codec so both modes round-trip through the same
// transport.

//|

///|
/// A one-based coordinate, refused at the field's own path. `noun` names what
/// the field is — "line" or "column" — which is all the two spellings of this
/// check ever differed by.
fn JsonObject::required_one_based(
  self : JsonObject,
  name : String,
  noun : String,
) -> Int raise @json.JsonDecodeError {
  let value = self.required_int(name)
  if value < 1 {
    raise JsonDecodeError(
      (self.path.add_key(name), "expected one-based " + noun),
    )
  }
  value
}

//|

///|
pub impl FromJson for SearchSemanticPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "semantic-search payload")
  {
    root: object.required_string("root"),
    patterns: object.required_string_array("patterns"),
    include_glob: object.required_string("include_glob"),
    exclude_glob: object.required_string("exclude_glob"),
    session_key: object.required_string("session_key"),
    generation: object.required_non_negative_int("generation"),
    max_results: object.required_non_negative_int("max_results"),
  }
}

//|

///|
pub impl ToJson for SearchSemanticPayload with fn to_json(self) {
  {
    "root": self.root,
    "patterns": self.patterns,
    "include_glob": self.include_glob,
    "exclude_glob": self.exclude_glob,
    "session_key": self.session_key,
    "generation": self.generation,
    "max_results": self.max_results,
  }
}

//|

///|
pub impl FromJson for CancelSearchSemanticPayload with fn from_json(json, path) {
  let object = JsonObject::decode(
    json, path, "semantic-search cancellation payload",
  )
  {
    session_key: object.required_string("session_key"),
    generation: object.required_non_negative_int("generation"),
  }
}

//|

///|
pub impl ToJson for CancelSearchSemanticPayload with fn to_json(self) {
  { "session_key": self.session_key, "generation": self.generation }
}

//|

///|
pub impl FromJson for SemanticContextLine with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "semantic-search context line")
  let line = object.required_one_based("line", "line")
  {
    line,
    text: object.required_string("text"),
    is_match: object.required_bool("is_match"),
  }
}

//|

///|
pub impl ToJson for SemanticContextLine with fn to_json(self) {
  { "line": self.line, "text": self.text, "is_match": self.is_match }
}

//|

///|
pub impl FromJson for SemanticSearchHit with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "semantic-search hit")
  let start_line = object.required_one_based("start_line", "line")
  let start_column = object.required_one_based("start_column", "column")
  let end_line = object.required_one_based("end_line", "line")
  let end_column = object.required_one_based("end_column", "column")
  if end_line < start_line ||
    (end_line == start_line && end_column < start_column) {
    raise JsonDecodeError((path, "semantic-search hit range must be forward"))
  }
  let context : Array[SemanticContextLine] = object.required_array_of(
    "source_context",
  )
  let description = object.optional_string("description")
  {
    path: object.required_string("path"),
    rule_id: object.required_string("rule_id"),
    description,
    start_line,
    start_column,
    end_line,
    end_column,
    matched_source: object.required_string("matched_source"),
    source_context: context,
  }
}

//|

///|
pub impl ToJson for SemanticSearchHit with fn to_json(self) {
  let fields : Map[String, Json] = {
    "path": self.path.to_json(),
    "rule_id": self.rule_id.to_json(),
    "start_line": self.start_line.to_json(),
    "start_column": self.start_column.to_json(),
    "end_line": self.end_line.to_json(),
    "end_column": self.end_column.to_json(),
    "matched_source": self.matched_source.to_json(),
    "source_context": self.source_context.to_json(),
  }
  set_optional(fields, "description", self.description)
  Json(fields)
}

//|

///|
pub impl FromJson for SemanticSearchError with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "semantic-search error")
  let code = object.required_string("code")
  let message = object.required_string("message")
  if code.is_empty() {
    raise JsonDecodeError((path.add_key("code"), "expected non-empty code"))
  }
  if message.is_empty() {
    raise JsonDecodeError(
      (path.add_key("message"), "expected non-empty message"),
    )
  }
  let result : SemanticSearchError = { code, message, }
  result
}

//|

///|
pub impl ToJson for SemanticSearchError with fn to_json(self) {
  { "code": self.code, "message": self.message }
}

//|

///|
pub impl FromJson for SearchSemanticReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "semantic-search reply")
  let generation = object.required_non_negative_int("generation")
  let match_count = object.required_non_negative_int("match_count")
  let file_count = object.required_non_negative_int("file_count")
  let hits : Array[SemanticSearchHit] = object.required_array_of("matches")
  let error : SemanticSearchError? = match optional_error_pair(object) {
    Some((code, message)) => Some({ code, message, })
    None => None
  }
  {
    root: object.required_string("root"),
    generation,
    matches: hits,
    match_count,
    file_count,
    limit_hit: object.required_bool("limit_hit"),
    cancelled: object.required_bool("cancelled"),
    partial: object.required_bool("partial"),
    error,
  }
}

//|

///|
pub impl ToJson for SearchSemanticReply with fn to_json(self) {
  let fields : Map[String, Json] = {
    "root": self.root.to_json(),
    "generation": self.generation.to_json(),
    "matches": self.matches.to_json(),
    "match_count": self.match_count.to_json(),
    "file_count": self.file_count.to_json(),
    "limit_hit": self.limit_hit.to_json(),
    "cancelled": self.cancelled.to_json(),
    "partial": self.partial.to_json(),
  }
  if self.error is Some(error) {
    fields["error_code"] = error.code.to_json()
    fields["error_message"] = error.message.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for SemanticSearchProgressPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(
    json, path, "semantic-search progress payload",
  )
  let matches : Array[SemanticSearchHit] = object.required_array_of("matches")
  {
    root: object.required_string("root"),
    session_key: object.required_string("session_key"),
    generation: object.required_non_negative_int("generation"),
    matches,
    match_count: object.required_non_negative_int("match_count"),
    file_count: object.required_non_negative_int("file_count"),
  }
}

///|
pub impl ToJson for SemanticSearchProgressPayload with fn to_json(self) {
  {
    "root": self.root,
    "session_key": self.session_key,
    "generation": self.generation,
    "matches": self.matches,
    "match_count": self.match_count,
    "file_count": self.file_count,
  }
}
