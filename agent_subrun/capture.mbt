///|
/// The `parse` a capture tool wants, assembled from a report's own decoder
/// and contract validator: a decode failure becomes a single problem, and a
/// decoded-but-invalid report becomes the validator's problem list. Both
/// reject, so the model retries instead of finishing with an unusable report.
pub fn[T] validated(
  parsed : Result[T, String],
  validate : (T) -> Array[String],
) -> Result[T, Array[String]] {
  match parsed {
    Err(message) => Err([message])
    Ok(report) => {
      let problems = validate(report)
      if problems.is_empty() {
        Ok(report)
      } else {
        Err(problems)
      }
    }
  }
}

///|
/// Build a submit-style capture tool: the child calls it exactly once with
/// its structured result; `parse` validates, a valid value is captured into
/// the runner-owned ref, and the run ends via `Control(Finish)`. Invalid
/// output is rejected with an error result so the model retries instead of
/// finishing with nothing.
///
/// Declared a control tool: its action is loop flow with a few bytes of
/// result, so the context-ceiling salvage honors a pending capture instead
/// of skip-closing it — without this, a child hitting the ceiling on its
/// submitting step would lose its finished result.
pub fn[T] capture_tool(
  name~ : String,
  description~ : String,
  schema~ : @agent_tool.JsonSchema,
  parse~ : (Json) -> Result[T, Array[String]],
  captured : Ref[T?],
  finished_note? : (T) -> String = _value => "submitted",
) -> @agent_tool.AgentToolDefinition {
  @agent_tool.AgentToolDefinition(
    name~,
    description~,
    schema~,
    execute=Sync(args => {
      match parse(args) {
        Err(problems) =>
          @agent_tool.respond(
            "\{name} rejected: \{problems.join("; ")}",
            is_error=true,
            brief=name,
          )
        Ok(value) => {
          captured.val = Some(value)
          @agent_tool.ToolAction::finish(finished_note(value))
        }
      }
    }),
    control=true,
  )
}
