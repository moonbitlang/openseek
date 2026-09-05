// Explicit codecs for the Desktop text-search boundary. Unknown fields are
// ignored for forward evolution; every consumed field deliberately specifies
// missing, null, malformed, and encoded behavior.

///|

///|
fn require_text_search_non_negative(
  value : Int,
  path : @json.JsonPath,
) -> Int raise @json.JsonDecodeError {
  if value < 0 {
    raise JsonDecodeError((path, "expected non-negative integer"))
  }
  value
}

///|
pub impl FromJson for SearchTextPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "text-search payload")
  {
    root: object.required_string("root"),
    query: object.required_string("query"),
    regex: object.required_bool("regex"),
    case_sensitive: object.required_bool("case_sensitive"),
    whole_word: object.required_bool("whole_word"),
    include_glob: object.required_string("include_glob"),
    exclude_glob: object.required_string("exclude_glob"),
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

///|
pub impl ToJson for SearchTextPayload with fn to_json(self) {
  {
    "root": self.root,
    "query": self.query,
    "regex": self.regex,
    "case_sensitive": self.case_sensitive,
    "whole_word": self.whole_word,
    "include_glob": self.include_glob,
    "exclude_glob": self.exclude_glob,
    "session_key": self.session_key,
    "generation": self.generation,
    "max_results": self.max_results,
  }
}

///|
pub impl FromJson for CancelSearchTextPayload with fn from_json(json, path) {
  let object = JsonObject::decode(
    json, path, "text-search cancellation payload",
  )
  {
    session_key: object.required_string("session_key"),
    generation: require_text_search_non_negative(
      object.required_int("generation"),
      path.add_key("generation"),
    ),
  }
}

///|
pub impl ToJson for CancelSearchTextPayload with fn to_json(self) {
  { "session_key": self.session_key, "generation": self.generation }
}

///|
pub impl FromJson for TextSearchRange with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "text-search range")
  let start_column = object.required_int("start_column")
  let end_column = object.required_int("end_column")
  if start_column < 1 {
    raise JsonDecodeError(
      (path.add_key("start_column"), "expected one-based column"),
    )
  }
  if end_column < start_column {
    raise JsonDecodeError(
      (path.add_key("end_column"), "expected an exclusive end column"),
    )
  }
  { start_column, end_column, }
}

///|
pub impl ToJson for TextSearchRange with fn to_json(self) {
  { "start_column": self.start_column, "end_column": self.end_column }
}

///|
pub impl FromJson for TextSearchMatch with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "text-search match")
  let line_number = object.required_int("line_number")
  let preview_start_column = object.required_int("preview_start_column")
  if line_number < 1 {
    raise JsonDecodeError(
      (path.add_key("line_number"), "expected one-based line number"),
    )
  }
  if preview_start_column < 1 {
    raise JsonDecodeError(
      (path.add_key("preview_start_column"), "expected one-based column"),
    )
  }
  let ranges : Array[TextSearchRange] = object.required_array_of("ranges")
  if ranges.is_empty() {
    raise JsonDecodeError(
      (path.add_key("ranges"), "expected at least one match range"),
    )
  }
  {
    path: object.required_string("path"),
    line_number,
    preview: object.required_string("preview"),
    preview_start_column,
    ranges,
  }
}

///|
pub impl ToJson for TextSearchMatch with fn to_json(self) {
  {
    "path": self.path,
    "line_number": self.line_number,
    "preview": self.preview,
    "preview_start_column": self.preview_start_column,
    "ranges": self.ranges,
  }
}

///|
pub impl FromJson for SearchTextReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "text-search reply")
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
  let matches : Array[TextSearchMatch] = object.required_array_of("matches")
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
      let pair : TextSearchError = { code, message, }
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
    matches,
    match_count,
    file_count,
    limit_hit: object.required_bool("limit_hit"),
    cancelled: object.required_bool("cancelled"),
    error,
  }
}

///|
pub impl ToJson for SearchTextReply with fn to_json(self) {
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
  Json(fields)
}
