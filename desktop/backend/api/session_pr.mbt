///|
fn ApiState::session_pr_tools(self : ApiState) -> Array[@mcp.Tool] {
  [
    {
      name: "session_pr_list",
      description: "List the pull request and remote branch URLs bound to the current session. Returns {bindings: [{url: ...}]}. Read this before changing the list.",
      input_schema: {
        "type": "object",
        "properties": {},
        "additionalProperties": false,
      },
      call: call => {
        guard call.arguments is Object(fields) && fields.is_empty() else {
          raise @mcp.ToolError("session_pr_list takes an empty object")
        }
        @engine.session_pr_list(self.manager, call.session)
        .to_json()
        .stringify()
      },
    },
    {
      name: "session_pr_bind",
      description: "Replace ALL pull request and remote branch associations for the current session. Pass {bindings: [{url: HTTPS_URL}, ...]}; omitted old entries are removed and [] clears all. Read session_pr_list first and retain entries you still want. Duplicate URLs are removed. This only saves associations; it does not check out code or validate remote existence. Bind PRs you create or work on, not incidental reference links.",
      input_schema: {
        "type": "object",
        "properties": {
          "bindings": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "url": {
                  "type": "string",
                  "description": "HTTPS pull request or remote branch URL.",
                },
              },
              "required": ["url"],
              "additionalProperties": false,
            },
          },
        },
        "required": ["bindings"],
        "additionalProperties": false,
      },
      call: call => {
        guard call.arguments is Object(fields) &&
          fields.length() == 1 &&
          fields.contains("bindings") else {
          raise @mcp.ToolError("session_pr_bind requires only a bindings array")
        }
        let bindings : @protocol.SessionPrBindings = @json.from_json(
          call.arguments,
        )
        self.save_session_pr(call.session, _ => bindings).to_json().stringify()
      },
    },
  ]
}

///|
async fn ApiState::save_session_pr(
  self : ApiState,
  session : String,
  update : (@protocol.SessionPrBindings) -> @protocol.SessionPrBindings,
) -> @protocol.SessionPrBindings {
  @engine.session_pr_update(self.manager, session, update, () => {
    self.publish(SessionPrChanged({ session, }))
  })
}
