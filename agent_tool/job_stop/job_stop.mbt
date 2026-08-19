///|
/// Tool `job_stop`: cancel a running background job by its job_id.
pub fn definition(
  bg_runtime : @bgjobs.BgJobRuntime,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="job_stop",
    description=(
      #|Stop a running background job by its job_id (from run_moonbit's
      #|run_in_background). Cancels the process; a job that already finished is a no-op.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": { "job_id": { "type": "string" } },
      "required": ["job_id"],
    }),
    execute=Async(arguments => execute(bg_runtime, arguments)),
  )
}

///|
async fn execute(
  bg_runtime : @bgjobs.BgJobRuntime,
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "job_id": String(job_id), .. } else {
    return @agent_tool.ToolAction::respond(
      "error: job_stop requires a string job_id",
      is_error=true,
    )
  }
  if bg_runtime.stop(job_id) {
    @agent_tool.ToolAction::respond("stopped background job \{job_id}")
  } else {
    @agent_tool.ToolAction::respond(
      "error: no background job with id \{job_id}",
      is_error=true,
    )
  }
}
