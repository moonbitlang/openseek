// Explicit codecs for the Desktop semantic-search boundary. Unknown fields
// are ignored for forward evolution; every consumed field deliberately
// specifies missing, null, malformed, and encoded behavior. The wire shapes
// mirror the text-search codec so both modes round-trip through the same
// transport.

//|

///|
fn sem_one_based_line(
  value : Int,
  path : @json.JsonPath,
  name : String,
) -> Int raise @json.JsonDecodeError {
  if value < 1 {
    raise JsonDecodeError((path.add_key(name), "expected one-based line"))
  }
  value
}

//|

///|
fn sem_one_based_column(
  value : Int,
  path : @json.JsonPath,
  name : String,
) -> Int raise @json.JsonDecodeError {
  if value < 1 {
    raise JsonDecodeError((path.add_key(name), "expected one-based column"))
  }
  value
}

//|

///|
pub impl FromJson for SearchSemanticPayload with fn from_json(json, path) {
  let object = TextSearchJsonObject::decode(
    json, path, "semantic-search payload",
  )
  {
    root: object.required_string("root"),
    query: object.required_string("query"),
    rules_dir: object.required_string("rules_dir"),
    enable_builtin_rules: object.required_bool("enable_builtin_rules"),
    session_key: object.required_string("session_key"),
    generation: require_text_search_non_negative(
      object.required_int("generation"),
      path.add_key("generation"),
    ),
    max_results: require_text_search_non_negative(
      object.required_int("max_results"),
      path.add_key("max_results"),
    ),
  }
}

//|

///|
pub impl ToJson for SearchSemanticPayload with fn to_json(self) {
  {
    "root": self.root,
    "query": self.query,
    "rules_dir": self.rules_dir,
    "enable_builtin_rules": self.enable_builtin_rules,
    "session_key": self.session_key,
    "generation": self.generation,
    "max_results": self.max_results,
  }
}

//|

///|
pub impl FromJson for CancelSearchSemanticPayload with fn from_json(json, path) {
  let object = TextSearchJsonObject::decode(
    json, path, "semantic-search cancellation payload",
  )
  {
    session_key: object.required_string("session_key"),
    generation: require_text_search_non_negative(
      object.required_int("generation"),
      path.add_key("generation"),
    ),
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
  let object = TextSearchJsonObject::decode(
    json, path, "semantic-search context line",
  )
  let line = sem_one_based_line(object.required_int("line"), path, "line")
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
  let object = TextSearchJsonObject::decode(json, path, "semantic-search hit")
  let start_line = sem_one_based_line(
    object.required_int("start_line"),
    path,
    "start_line",
  )
  let start_column = sem_one_based_column(
    object.required_int("start_column"),
    path,
    "start_column",
  )
  let end_line = sem_one_based_line(
    object.required_int("end_line"),
    path,
    "end_line",
  )
  let end_column = sem_one_based_column(
    object.required_int("end_column"),
    path,
    "end_column",
  )
  if end_line < start_line ||
    (end_line == start_line && end_column < start_column) {
    raise JsonDecodeError((path, "semantic-search hit range must be forward"))
  }
  let context : Array[SemanticContextLine] = []
  for index, raw in object.required_array("source_context") {
    context.push(
      @json.from_json(raw, path=path.add_key("source_context").add_index(index)),
    )
  }
  let description = match object.fields.get("description") {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("description"), "expected string or null"),
      )
  }
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
  if self.description is Some(description) {
    fields["description"] = description.to_json()
  }
  Json::object(fields)
}

//|

///|
pub impl FromJson for SemanticSearchError with fn from_json(json, path) {
  let object = TextSearchJsonObject::decode(json, path, "semantic-search error")
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
  let result : SemanticSearchError = { code, message }
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
  let object = TextSearchJsonObject::decode(json, path, "semantic-search reply")
  let generation = require_text_search_non_negative(
    object.required_int("generation"),
    path.add_key("generation"),
  )
  let match_count = require_text_search_non_negative(
    object.required_int("match_count"),
    path.add_key("match_count"),
  )
  let file_count = require_text_search_non_negative(
    object.required_int("file_count"),
    path.add_key("file_count"),
  )
  let hits : Array[SemanticSearchHit] = []
  for index, raw in object.required_array("matches") {
    hits.push(
      @json.from_json(raw, path=path.add_key("matches").add_index(index)),
    )
  }
  let error_code = object.optional_string("error_code")
  let error_message = object.optional_string("error_message")
  let error = match (error_code, error_message) {
    (None, None) => None
    (Some(code), Some(message)) => {
      if code.is_empty() {
        raise JsonDecodeError(
          (path.add_key("error_code"), "expected non-empty error code"),
        )
      }
      if message.is_empty() {
        raise JsonDecodeError(
          (path.add_key("error_message"), "expected non-empty error message"),
        )
      }
      let pair : SemanticSearchError = { code, message }
      Some(pair)
    }
    _ =>
      raise JsonDecodeError(
        (path, "error_code and error_message must be present together"),
      )
  }
  {
    root: object.required_string("root"),
    generation,
    matches: hits,
    match_count,
    file_count,
    limit_hit: object.required_bool("limit_hit"),
    cancelled: object.required_bool("cancelled"),
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
  }
  if self.error is Some(error) {
    fields["error_code"] = error.code.to_json()
    fields["error_message"] = error.message.to_json()
  }
  Json::object(fields)
}
