///|
priv struct StreamToolCall {
  mut id : String
  mut name : String
  arguments : StringBuilder
}

///|
fn StreamToolCall::StreamToolCall() -> StreamToolCall {
  { id: "", name: "", arguments: StringBuilder::new() }
}

///|
fn StreamToolCall::to_json(self : StreamToolCall) -> Json {
  {
    "id": self.id,
    "type": "function",
    "function": { "name": self.name, "arguments": self.arguments.to_string() },
  }
}

///|
priv struct StreamAccumulator {
  content : StringBuilder
  reasoning_content : StringBuilder
  tool_calls : Array[StreamToolCall]
  mut usage : Json?
}

///|
fn StreamAccumulator::StreamAccumulator() -> StreamAccumulator {
  {
    content: StringBuilder::new(),
    reasoning_content: StringBuilder::new(),
    tool_calls: [],
    usage: None,
  }
}

///|
fn StreamAccumulator::ensure_tool_call(
  self : StreamAccumulator,
  index : Int,
) -> StreamToolCall {
  while self.tool_calls.length() <= index {
    self.tool_calls.push(StreamToolCall())
  }
  self.tool_calls[index]
}

///|
fn StreamAccumulator::response(
  self : StreamAccumulator,
) -> @deepseek.ChatResponse raise {
  let reasoning_content = self.reasoning_content.to_string()
  let message = Json::object(
    Map(
      [
        ("content", Json::string(self.content.to_string())),
        ..if reasoning_content != "" {
          [("reasoning_content", Json::string(reasoning_content))]
        } else {
          []
        },
        ..if self.tool_calls.length() > 0 {
          [
            (
              "tool_calls",
              ([ for call in self.tool_calls => call.to_json() ] : Json),
            ),
          ]
        } else {
          []
        },
      ],
    ),
  )
  let envelope = Json::object(
    Map(
      [
        ("choices", ([({ "message": message } : Json)] : Json)),
        ..match self.usage {
          Some(usage) => [("usage", usage)]
          None => []
        },
      ],
    ),
  )
  @json.from_json(envelope)
}

///|
fn json_string_field(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_int_field(fields : Map[String, Json], key : String) -> Int? {
  match fields.get(key) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn apply_tool_call_delta(
  acc : StreamAccumulator,
  json : Json,
  fallback_index : Int,
) -> Unit {
  let fields = match json {
    Object(fields) => fields
    _ => return
  }
  let index = json_int_field(fields, "index").unwrap_or(fallback_index)
  if index < 0 {
    return
  }
  let call = acc.ensure_tool_call(index)
  if json_string_field(fields, "id") is Some(id) && id != "" {
    call.id = id
  }
  guard fields.get("function") is Some(Object(function)) else { return }
  if json_string_field(function, "name") is Some(name) && name != "" {
    call.name = name
  }
  if json_string_field(function, "arguments") is Some(arguments) &&
    arguments != "" {
    call.arguments.write_string(arguments)
  }
}

///|
async fn apply_stream_delta(
  acc : StreamAccumulator,
  delta : Map[String, Json],
  on_content_delta~ : async (String) -> Unit,
  on_reasoning_delta~ : async (String) -> Unit,
) -> Unit {
  if json_string_field(delta, "content") is Some(content) && content != "" {
    acc.content.write_string(content)
    on_content_delta(content)
  }
  if json_string_field(delta, "reasoning_content") is Some(reasoning) &&
    reasoning != "" {
    acc.reasoning_content.write_string(reasoning)
    on_reasoning_delta(reasoning)
  }
  match delta.get("tool_calls") {
    Some(Array(calls)) =>
      for index, call in calls {
        apply_tool_call_delta(acc, call, index)
      }
    _ => ()
  }
}

///|
async fn apply_stream_json(
  acc : StreamAccumulator,
  json : Json,
  on_content_delta~ : async (String) -> Unit,
  on_reasoning_delta~ : async (String) -> Unit,
) -> Unit {
  match json {
    { "usage": Null, .. } => ()
    { "usage": usage_json, .. } => acc.usage = Some(usage_json)
    _ => ()
  }
  match json {
    { "choices": [{ "delta": Object(delta), .. }, ..], .. } =>
      apply_stream_delta(acc, delta, on_content_delta~, on_reasoning_delta~)
    { "choices": [], .. } => ()
    _ => ()
  }
}

///|
fn sse_data_fragment(raw : String) -> String? {
  let line = if raw.has_suffix("\r") {
    raw[:raw.length() - 1].to_owned()
  } else {
    raw
  }
  if line.has_prefix("data:") {
    Some(line[5:].trim().to_owned())
  } else {
    None
  }
}

///|
async fn flush_sse_event(
  acc : StreamAccumulator,
  data_lines : Array[String],
  on_content_delta~ : async (String) -> Unit,
  on_reasoning_delta~ : async (String) -> Unit,
) -> Bool {
  if data_lines.length() == 0 {
    return false
  }
  let data = data_lines.join("\n").trim().to_owned()
  data_lines.clear()
  if data == "[DONE]" {
    return true
  }
  apply_stream_json(
    acc,
    @json.parse(data),
    on_content_delta~,
    on_reasoning_delta~,
  )
  false
}

///|
async fn read_chat_stream(
  reader : @http.Client,
  on_content_delta~ : async (String) -> Unit,
  on_reasoning_delta~ : async (String) -> Unit,
) -> @deepseek.ChatResponse {
  let acc = StreamAccumulator::StreamAccumulator()
  let data_lines : Array[String] = []
  for ;; {
    match reader.read_until("\n") {
      None => {
        if flush_sse_event(
            acc,
            data_lines,
            on_content_delta~,
            on_reasoning_delta~,
          ) {
          break
        }
        fail("DeepSeek stream ended before [DONE]")
      }
      Some(raw) => {
        let trimmed = raw.trim()
        if trimmed.is_empty() {
          if flush_sse_event(
              acc,
              data_lines,
              on_content_delta~,
              on_reasoning_delta~,
            ) {
            break
          }
        } else if sse_data_fragment(raw) is Some(data) {
          data_lines.push(data)
        }
      }
    }
  }
  acc.response()
}
