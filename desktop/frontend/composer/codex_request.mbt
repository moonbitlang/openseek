///|
priv struct CodexRequestQuestion {
  id : String
  header : String
  question : String
  options : Array[(String, String)]
}

///|
/// The string members of a JSON array; every other value is ignored.
fn json_string_parts(values : Array[Json]) -> Array[String] {
  [
    for value in values if value is String(part) => part
  ]
}

///|
/// Render only the approval facts needed for a decision. The complete payload
/// remains available below for diagnostics and fields this client does not yet
/// understand.
fn CodexRequestInput::approval_details(
  self : CodexRequestInput,
) -> Array[@html.Html] {
  guard self.params is Object(fields) else { return [] }
  let details : Array[@html.Html] = []
  let network_request = fields.get("networkApprovalContext") is Some(Object(_))
  if network_request &&
    fields.get("networkApprovalContext") is Some(Object(network)) &&
    @jsonx.json_text(network, "host") is Some(host) {
    let protocol = @jsonx.json_text(network, "protocol")
    let port = network
      .get("port")
      .bind(value => {
        match value {
          String(port) => Some(port)
          Number(_) => Some(value.stringify())
          _ => None
        }
      })
    let destination = if protocol is Some(protocol) && port is Some(port) {
      "\{protocol}://\{host}:\{port}"
    } else if protocol is Some(protocol) {
      "\{protocol}://\{host}"
    } else if port is Some(port) {
      "\{host}:\{port}"
    } else {
      host
    }
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Network destination"),
        @html.code(class="codex-request-value", destination),
      ]),
    )
  }
  if !network_request {
    let commands : Array[String] = []
    if @jsonx.json_text(fields, "command") is Some(command) {
      commands.push(command)
    } else if fields.get("commandActions") is Some(Array(actions)) {
      for action in actions {
        if action is Object(action_fields) &&
          @jsonx.json_text(action_fields, "command") is Some(command) {
          commands.push(command)
        }
      }
    }
    if !commands.is_empty() {
      details.push(
        @html.div(class="codex-request-detail", [
          @html.div(class="codex-request-detail-label", "Command"),
          @html.pre(class="codex-request-command", commands.join("\n")),
        ]),
      )
    }
  }
  if @jsonx.json_text(fields, "cwd") is Some(cwd) && !cwd.is_empty() {
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Working directory"),
        @html.code(class="codex-request-value", cwd),
      ]),
    )
  }
  if fields.get("proposedExecpolicyAmendment") is Some(Array(values)) {
    let parts = json_string_parts(values)
    if !parts.is_empty() {
      details.push(
        @html.div(class="codex-request-detail", [
          @html.div(class="codex-request-detail-label", "Requested rule"),
          @html.code(class="codex-request-value", parts.join(" ")),
        ]),
      )
    }
  }
  if @jsonx.json_text(fields, "grantRoot") is Some(grant_root) &&
    !grant_root.is_empty() {
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Allowed path"),
        @html.code(class="codex-request-value", grant_root),
      ]),
    )
  }
  if fields.get("additionalPermissions") is Some(additional_permissions) &&
    !(additional_permissions is Null) {
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Additional permissions"),
        @html.pre(
          class="codex-request-command",
          additional_permissions.stringify(indent=2),
        ),
      ]),
    )
  }
  details
}

///|
/// Use the server's advertised choices. Older app-server builds omitted them,
/// so command and file approvals retain their established three-button set.
fn CodexRequestInput::approval_decisions(
  self : CodexRequestInput,
) -> Array[Json] {
  if self.params is Object(fields) &&
    fields.get("availableDecisions") is Some(Array(decisions)) {
    return decisions
  }
  match self.method_ {
    "item/commandExecution/requestApproval"
    | "item/fileChange/requestApproval" =>
      [Json("accept"), Json("acceptForSession"), Json("decline")]
    _ => []
  }
}

///|
/// Name an execution-policy choice with its exact command prefix. The
/// decision object is authoritative; the top-level proposal is a fallback for
/// older request payloads.
fn CodexRequestInput::execpolicy_label(
  self : CodexRequestInput,
  decision : Json,
) -> String {
  let mut parts : Array[String] = []
  if decision is Object(decision_fields) &&
    decision_fields.get("acceptWithExecpolicyAmendment")
    is Some(Object(amendment)) &&
    amendment.get("execpolicy_amendment") is Some(Array(values)) {
    parts = json_string_parts(values)
  }
  if parts.is_empty() &&
    self.params is Object(fields) &&
    fields.get("proposedExecpolicyAmendment") is Some(Array(values)) {
    parts = json_string_parts(values)
  }
  if parts.is_empty() {
    "Allow by rule"
  } else {
    "Allow by rule: \{parts.join(" ")}"
  }
}

///|
fn CodexRequestInput::approval_actions(
  self : CodexRequestInput,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  let controls : Array[@html.Html] = []
  for decision in self.approval_decisions() {
    match decision {
      String("accept") =>
        controls.push(
          @html.button(
            class="codex-request-action codex-request-action-primary",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision~,
              ),
            ),
            "Approve once",
          ),
        )
      String("acceptForSession") =>
        controls.push(
          @html.button(
            class="codex-request-action",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision~,
              ),
            ),
            "Approve for session",
          ),
        )
      String("decline") =>
        controls.push(
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision~,
              ),
            ),
            "Decline",
          ),
        )
      String("cancel") =>
        controls.push(
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision~,
              ),
            ),
            "Cancel",
          ),
        )
      Object(fields) if fields.get("acceptWithExecpolicyAmendment") is Some(_) =>
        controls.push(
          @html.button(
            class="codex-request-action",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision~,
              ),
            ),
            self.execpolicy_label(decision),
          ),
        )
      _ => ()
    }
  }
  if controls.is_empty() {
    controls.push(
      @html.span(
        class="codex-request-unsupported",
        "This app version cannot answer the advertised approval choices.",
      ),
    )
  }
  @html.div(class="codex-request-actions", controls)
}

///|
fn CodexRequestInput::questions(
  self : CodexRequestInput,
) -> Array[CodexRequestQuestion] {
  guard self.params is Object(fields) &&
    fields.get("questions") is Some(Array(values)) else {
    return []
  }
  let questions : Array[CodexRequestQuestion] = []
  for value in values {
    guard value is Object(question) &&
      @jsonx.json_text(question, "id") is Some(id) else {
      continue
    }
    let options : Array[(String, String)] = []
    if question.get("options") is Some(Array(values)) {
      for value in values {
        if value is Object(option) &&
          @jsonx.json_text(option, "label") is Some(label) {
          options.push(
            (label, @jsonx.json_text(option, "description").unwrap_or("")),
          )
        }
      }
    }
    questions.push({
      id,
      header: @jsonx.json_text(question, "header").unwrap_or("Question"),
      question: @jsonx.json_text(question, "question").unwrap_or(""),
      options,
    })
  }
  questions
}

///|
fn CodexRequestInput::raw_details(
  self : CodexRequestInput,
  open~ : Bool,
) -> @html.Html {
  @html.details(class="codex-request-raw", open~, [
    @html.summary(class="codex-request-raw-summary", "Show details"),
    @html.pre(class="codex-raw", self.params.stringify(indent=2)),
  ])
}

///|
fn CodexRequestInput::render(
  self : CodexRequestInput,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  let body : Array[@html.Html] = [
    @html.div(
      class="codex-request-title",
      match self.method_ {
        "item/commandExecution/requestApproval" =>
          if self.params is Object(fields) &&
            fields.get("networkApprovalContext") is Some(Object(_)) {
            "Network access approval"
          } else {
            "Command approval"
          }
        "item/fileChange/requestApproval" => "File change approval"
        "item/permissions/requestApproval" => "Permission request"
        "item/tool/requestUserInput" => "Codex needs your input"
        "mcpServer/elicitation/request" => "Tool request"
        other => other
      },
    ),
  ]
  if self.params is Object(fields) &&
    @jsonx.json_text(fields, "reason") is Some(reason) &&
    !reason.is_empty() {
    body.push(@html.p(class="codex-request-reason", reason))
  }
  match self.method_ {
    "item/commandExecution/requestApproval"
    | "item/fileChange/requestApproval" => {
      let details = self.approval_details()
      if !details.is_empty() {
        body.push(@html.div(class="codex-request-details", details))
      }
      body.push(self.raw_details(open=details.is_empty()))
      body.push(self.approval_actions(identity, action_emit))
    }
    "item/permissions/requestApproval" => {
      body.push(@html.pre(class="codex-raw", self.params.stringify(indent=2)))
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="codex-request-action codex-request-action-primary",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision=Json("accept"),
              ),
            ),
            "Grant for turn",
          ),
          @html.button(
            class="codex-request-action",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision=Json("acceptForSession"),
              ),
            ),
            "Grant for session",
          ),
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision=Json("decline"),
              ),
            ),
            "Deny",
          ),
        ]),
      )
    }
    "item/tool/requestUserInput" => {
      for question in self.questions() {
        let answer = self.answers.get(question.id).unwrap_or("")
        let controls : Array[@html.Html] = [
          @html.div(class="codex-question-header", question.header),
          @html.div(class="codex-question-text", question.question),
        ]
        if !question.options.is_empty() {
          let options : Array[@html.Html] = []
          for option in question.options {
            options.push(
              @html.button(
                class=if answer == option.0 {
                  "codex-option selected"
                } else {
                  "codex-option"
                },
                on_click=action_emit(
                  CodexRequestAnswerChanged(
                    identity~,
                    request_key=self.request_key,
                    question_id=question.id,
                    answer=option.0,
                  ),
                ),
                [
                  @html.span(class="codex-option-label", option.0),
                  @html.span(class="codex-option-desc", option.1),
                ],
              ),
            )
          }
          controls.push(@html.div(class="codex-options", options))
        }
        controls.push(
          @html.input(
            value=answer,
            placeholder="Type an answer",
            on_input=action_emit.map(value => {
              CodexRequestAnswerChanged(
                identity~,
                request_key=self.request_key,
                question_id=question.id,
                answer=value,
              )
            }),
            attrs=@html.Attrs::build().data_set("focus-owner", ""),
          ),
        )
        body.push(@html.div(class="codex-question", controls))
      }
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="codex-request-action codex-request-action-primary",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision=Json("accept"),
              ),
            ),
            "Submit answers",
          ),
        ]),
      )
    }
    "mcpServer/elicitation/request" => {
      body.push(@html.pre(class="codex-raw", self.params.stringify(indent=2)))
      body.push(
        @html.textarea(
          value=self.answers.get("__content").unwrap_or("{}"),
          placeholder="JSON content required by the tool",
          on_input=action_emit.map(value => {
            CodexRequestAnswerChanged(
              identity~,
              request_key=self.request_key,
              question_id="__content",
              answer=value,
            )
          }),
          attrs=@html.Attrs::build().data_set("focus-owner", ""),
          "",
        ),
      )
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="codex-request-action codex-request-action-primary",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision=Json("accept"),
              ),
            ),
            "Submit JSON",
          ),
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=action_emit(
              CodexRequestResponded(
                identity~,
                request_key=self.request_key,
                decision=Json("decline"),
              ),
            ),
            "Decline",
          ),
        ]),
      )
    }
    _ =>
      body.push(
        @html.pre(
          class="codex-raw danger",
          "Unsupported app-server request:\n" + self.params.stringify(indent=2),
        ),
      )
  }
  @html.section(class="codex-request", body)
}
