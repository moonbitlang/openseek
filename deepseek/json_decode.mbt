///|
fn Usage::parse_json(
  json : Json,
  path : @json.JsonPath,
) -> Usage raise @json.JsonDecodeError {
  match json {
    {
      "prompt_tokens"? : Some(Number(prompt_tokens, ..))
      | (None with prompt_tokens = 0),
      "completion_tokens"? : Some(Number(completion_tokens, ..))
      | (None with completion_tokens = 0),
      "total_tokens"? : Some(Number(total_tokens, ..))
      | (None with total_tokens = 0),
      "prompt_cache_hit_tokens"? : Some(Number(prompt_cache_hit_tokens, ..))
      | (None with prompt_cache_hit_tokens = 0),
      "prompt_cache_miss_tokens"? : Some(Number(prompt_cache_miss_tokens, ..))
      | (None with prompt_cache_miss_tokens = 0),
      ..
    } =>
      {
        prompt_tokens: prompt_tokens.to_int(),
        completion_tokens: completion_tokens.to_int(),
        total_tokens: total_tokens.to_int(),
        prompt_cache_hit_tokens: prompt_cache_hit_tokens.to_int(),
        prompt_cache_miss_tokens: prompt_cache_miss_tokens.to_int(),
      }
    _ =>
      json_decode_error(
        path, "Usage::from_json: expected object with numeric fields",
      )
  }
}

///|
fn Usage::empty() -> Usage {
  {
    prompt_tokens: 0,
    completion_tokens: 0,
    total_tokens: 0,
    prompt_cache_hit_tokens: 0,
    prompt_cache_miss_tokens: 0,
  }
}

///|
fn[T] json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
impl FromJson for ToolCall with fn from_json(json : Json, path : @json.JsonPath) -> ToolCall {
  match json {
    {
      "id": String(id),
      "function": { "name": String(name), "arguments": String(arguments), .. },
      ..
    } => ToolCall(id~, name~, arguments~)
    { "id": String(_), "function": { "name": String(_), .. }, .. } =>
      json_decode_error(
        path.add_key("function").add_key("arguments"),
        "ToolCall::from_json: expected function.arguments",
      )
    Object({ "id": String(_), "function": Object(_), .. }) =>
      json_decode_error(
        path.add_key("function").add_key("name"),
        "ToolCall::from_json: expected function.name",
      )
    Object({ "id": String(_), .. }) =>
      json_decode_error(
        path.add_key("function"),
        "ToolCall::from_json: expected function object",
      )
    Object(_) =>
      json_decode_error(path.add_key("id"), "ToolCall::from_json: expected id")
    _ => json_decode_error(path, "ToolCall::from_json: expected object")
  }
}

///|
fn decode_nullable_string(
  fields : Map[String, Json],
  key~ : String,
  path~ : @json.JsonPath,
) -> String? raise @json.JsonDecodeError {
  match fields.get(key) {
    None => None
    Some(String(value)) => Some(value)
    Some(Null) => Some("")
    Some(_) =>
      json_decode_error(
        path.add_key(key),
        "ChatResponse::from_json: expected \{key} string",
      )
  }
}

///|
fn decode_reasoning_content(
  fields : Map[String, Json],
  path~ : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  match decode_nullable_string(fields, key="reasoning_content", path~) {
    Some(reasoning_content) => reasoning_content
    None => decode_nullable_string(fields, key="reasoning", path~).unwrap_or("")
  }
}

///|
/// Decodes a DeepSeek chat completions JSON response envelope.
///
/// Missing usage information is represented as zero token counts.
pub impl FromJson for ChatResponse with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ChatResponse {
  let message_path = path.add_key("choices").add_index(0).add_key("message")
  let (message_fields, usage_json) : (Map[String, Json], Json?) = match json {
    {
      "choices": [{ "message": Object(message_fields), .. }, ..],
      "usage"? : usage_json,
      ..
    } => (message_fields, usage_json)
    { "choices": [], .. } =>
      json_decode_error(
        path.add_key("choices"),
        "ChatResponse::from_json: empty choices",
      )
    { "choices": [Object(_), ..], .. } =>
      json_decode_error(
        message_path, "ChatResponse::from_json: expected message object",
      )
    { "choices": [_, ..], .. } =>
      json_decode_error(
        path.add_key("choices").add_index(0),
        "ChatResponse::from_json: expected choice object",
      )
    Object(_) =>
      json_decode_error(
        path.add_key("choices"),
        "ChatResponse::from_json: expected choices array",
      )
    _ =>
      json_decode_error(
        path, "ChatResponse::from_json: expected response object",
      )
  }
  let tool_calls : Array[ToolCall] = match message_fields {
    { "tool_calls": Array(raw_tool_calls), .. } =>
      [
        for index, raw_tool_call in raw_tool_calls => {
          FromJson::from_json(
            raw_tool_call,
            message_path.add_key("tool_calls").add_index(index),
          )
        }
      ]
    { "tool_calls": Null, .. } => []
    { "tool_calls": _, .. } =>
      json_decode_error(
        message_path.add_key("tool_calls"),
        "ChatResponse::from_json: expected tool_calls array",
      )
    _ => []
  }
  let content = match message_fields {
    { "content"? : Some(String(content)) | (Some(Null) with content = ""), .. } =>
      content
    { "content"? : None, .. } if tool_calls.length() > 0 => ""
    _ =>
      json_decode_error(
        message_path.add_key("content"),
        "ChatResponse::from_json: expected message content",
      )
  }
  let reasoning_content = decode_reasoning_content(
    message_fields,
    path=message_path,
  )
  let usage = match usage_json {
    Some(usage) => FromJson::from_json(usage, path.add_key("usage"))
    None => Usage::empty()
  }
  { content, reasoning_content, tool_calls, usage, }
}

///|
#doc(hidden)
#deprecated
pub extend ChatResponse with FromJson::{from_json}
