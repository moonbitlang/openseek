///|
pub fn Service::tool(
  questions : Service,
  validate : async (String) -> Unit,
  changed : () -> Unit,
) -> @mcp.Tool {
  {
    name: "ask_user",
    description: "Ask the user questions in this conversation. Supply unique question ids, clear titles, and optional suggested choices; the user can always type their own answer. This is for information and preferences, not permission approval. Waits up to 30 seconds. A pending result means the questions remain open: continue independent work without assuming an answer or asking the same questions again. Later answers (or a skip) are actively delivered to this conversation. Questions survive tool/turn completion and frontend reconnects, but not host shutdown.",
    input_schema: {
      "type": "object",
      "additionalProperties": false,
      "required": ["questions"],
      "properties": {
        "questions": {
          "type": "array",
          "minItems": 1,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "title"],
            "properties": {
              "id": { "type": "string", "minLength": 1 },
              "title": { "type": "string", "minLength": 1 },
              "options": {
                "type": "array",
                "items": { "type": "string", "minLength": 1 },
              },
            },
          },
        },
      },
    },
    call: call => {
      let payload : @protocol.AskUserPayload = @json.from_json(call.arguments)
      validate(call.session)
      let entry = questions.request(call.session, payload)
      changed()
      defer changed()
      [Text(questions.wait(entry).stringify())]
    },
  }
}
