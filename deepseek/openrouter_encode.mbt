///|
/// Encodes a DeepSeek V4 request for OpenRouter directly.
pub fn openrouter_encode_chat_request(
  model~ : DsVariant,
  thinking~ : ThinkingMode,
  tools? : Array[ToolDefinition] = [],
  stream? : Bool = false,
  response_format? : ResponseFormat,
  messages : Array[ChatMessage],
) -> Json {
  let model = match model {
    V4Flash => "deepseek/deepseek-v4-flash-0731"
    V4Pro => "deepseek/deepseek-v4-pro"
    V41Flash => "deepseek/deepseek-v4.1-flash"
  }
  let effort = match thinking {
    No => "none"
    High => "high"
    Max => "max"
  }
  Json(
    Map(
      [
        ("model", Json(model)),
        ("messages", ([ for message in messages => message ] : Json)),
        ("stream", Json(stream)),
        ("reasoning", { "effort": effort }),
        ..if response_format is Some(format) {
          [("response_format", ({ "type": "\{format}" } : Json))]
        },
        ..if stream {
          [("stream_options", ({ "include_usage": true } : Json))]
        },
        ..if tools.length() > 0 {
          [("tools", ([ for tool in tools => tool ] : Json))]
        },
      ],
    ),
  )
}
