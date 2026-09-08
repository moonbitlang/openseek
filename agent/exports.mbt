// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Model requests since the last plan activity — a successful `plan` call or
/// an injected reminder, whichever is more recent — before the loop injects a
/// plan staleness reminder. Fifty is roughly one reminder per MILESTONE of
/// work: the original ten mirrored Claude Code's 10-turn todo cadence, but an
/// openseek request is far smaller than a CC turn, and live long-horizon runs
/// showed the mismatch (40 nags against 14 actual plan calls in a 478-request
/// build — every nag replayed in context forever; issue #422). Re-nagging is
/// variant-dependent: with a recorded checklist the reminder re-surfaces real
/// state and may repeat, while the no-plan nudge fires at most once per turn —
/// a model that ignored "consider recording a plan" once gains nothing from
/// hearing it again.
pub let plan_reminder_after_steps : Int = 50

///|
/// Run a one-shot OpenSeek task and discard the returned session.
///
/// This is the highest-level convenience entry point. It creates a fresh
/// in-memory session with id `"one-shot"`, appends `task` as the first user
/// event, runs the agent loop, logs progress through the configured process
/// logger, and returns `Unit`. It does not persist the session and does not
/// expose the final `Session` value to the caller.
///
/// `system_prompt_text` is required. Prompt selection is intentionally owned by
/// the application layer, not by `agent`; this package does not depend on the
/// `prompt` package. `thinking` defaults to `Max`. `workspace_root` defaults to
/// `"."` and is passed into the per-turn `AgentRuntime`; local file and shell
/// tools resolve relative paths against that root. `api_url` is forwarded to
/// the DeepSeek client and is mainly useful for tests or compatible endpoints,
/// as are `retry_attempts` and `retry_backoff_ms`; omit either to keep the
/// client's own default.
///
/// Use `run_turn_with_append` when every committed event must be persisted as
/// the turn progresses, or `run_turn_in_scope` when runtime/tool state must span
/// turns.
pub async fn run(
  api_key~ : String,
  model~ : @deepseek.Model,
  task~ : String,
  system_prompt_text~ : String,
  max_steps? : Int = unbounded_max_steps,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  retry_attempts? : Int,
  retry_backoff_ms? : Int,
  workspace_root? : String = ".",
) -> Unit {
  let session = @agent_session.Session(
    SessionId("one-shot"),
    system_prompt=system_prompt_text,
  )
  ignore(
    run_turn_with_append(
      api_key~,
      model~,
      session~,
      task~,
      append_item=(session, item) => session.append(item),
      max_steps~,
      thinking~,
      api_url?,
      retry_attempts?,
      retry_backoff_ms?,
      workspace_root~,
    ),
  )
}
