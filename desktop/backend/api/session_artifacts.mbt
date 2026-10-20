///|
fn ApiState::artifact_tools(self : ApiState) -> Array[@mcp.Tool] {
  [
    {
      name: "artifacts_list",
      description: "List the pull request and remote branch URLs bound to the current session. Returns {artifacts: [{type, url}]}.",
      input_schema: {
        "type": "object",
        "properties": {},
        "additionalProperties": false,
      },
      call: call => {
        guard call.arguments is Object(fields) && fields.is_empty() else {
          raise @mcp.ToolError("artifacts_list takes an empty object")
        }
        @engine.session_artifacts_list(self.manager, call.session)
        .to_json()
        .stringify()
      },
    },
    {
      name: "artifacts_attach",
      description: "Attach one artifact to the current session. Requires {type: pull_request|branch, url: HTTPS_URL}. Appends atomically and deduplicates by type and URL; existing artifacts are retained. Associate work you create or work on, not incidental reference links. This does not check out code or validate remote existence. No detach or replacement tool is exposed to agents.",
      input_schema: {
        "type": "object",
        "properties": {
          "type": { "type": "string", "enum": ["pull_request", "branch"] },
          "url": {
            "type": "string",
            "description": "HTTPS pull request or remote branch URL.",
          },
        },
        "required": ["type", "url"],
        "additionalProperties": false,
      },
      call: call => {
        let artifact : @protocol.SessionArtifact = @json.from_json(
          call.arguments,
        )
        self
        .save_session_artifacts(call.session, current => {
          current.attach(artifact)
        })
        .to_json()
        .stringify()
      },
    },
  ]
}

///|
async fn ApiState::save_session_artifacts(
  self : ApiState,
  session : String,
  update : (@protocol.SessionArtifacts) -> @protocol.SessionArtifacts,
) -> @protocol.SessionArtifacts {
  @engine.session_artifacts_update(self.manager, session, update, () => {
    self.publish(SessionArtifactsChanged({ session, }))
  })
}
