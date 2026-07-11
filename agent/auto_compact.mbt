///|
/// Soft context ceiling, percent of the model window: at or past it the
/// turn ENDS at the current step's boundary — gracefully. A tool batch
/// measured in the soft band still executes (aggregate-budgeted, see
/// `soft_batch_fits`), the checkpoint covers its real results, and nothing
/// is discarded or re-issued. Crossings land in the soft band whenever one
/// round grows the context by less than the tier gap, which makes graceful
/// exits the common case. The guard is a ceiling guard, not a cost
/// optimization: rewriting the model-facing prefix busts DeepSeek
/// prefix-cache pricing, so it must fire only where the alternative is
/// request failure.
let soft_context_ceiling_percent = 70

///|
/// Hard context ceiling: at or past it no tool batch STARTS — every call
/// is skip-closed (completion salvage aside) so the checkpoint request
/// stays bounded by the measured usage plus a few bytes of notes. Only
/// reachable when a single round jumped the entire soft band, i.e. the
/// previous batch returned enormous results — exactly when more unmeasured
/// execution is dangerous. The headroom above must still fit the
/// summary-generation request, which resends the projected history plus
/// the checkpoint prompt.
let hard_context_ceiling_percent = 80

///|
/// Whether `tokens` reaches `percent` of the model's context window.
fn AgentLoop::at_context_share(
  self : Self,
  tokens : Int64,
  percent : Int,
) -> Bool {
  tokens * 100 >=
  self.client.model.context_window().to_int64() * percent.to_int64()
}

///|
/// The turn must end at this step's boundary. `total_tokens` — last prompt
/// plus completion — is the closest available proxy for the next request's
/// prompt size; `extra_result_chars` adds the current batch's recorded
/// results (measured AFTER usage was), so a below-threshold response whose
/// batch grew the context into the soft band still ends compacted.
fn AgentLoop::at_soft_context_ceiling(
  self : Self,
  usage : @deepseek.Usage,
  extra_result_chars? : Int64 = 0,
) -> Bool {
  self.at_context_share(
    usage.total_tokens.to_int64() + extra_result_chars,
    soft_context_ceiling_percent,
  )
}

///|
/// No tool batch may start; skip-close and yield.
fn AgentLoop::at_hard_context_ceiling(
  self : Self,
  usage : @deepseek.Usage,
) -> Bool {
  self.at_context_share(
    usage.total_tokens.to_int64(),
    hard_context_ceiling_percent,
  )
}

///|
/// Token allowance the checkpoint request needs beyond the projected
/// history: the checkpoint prompt and message wrappers on the prompt side,
/// PLUS the completion budget the summary itself is generated into — a
/// budget that lets a batch push the projection to the window edge would
/// leave the summary no room to be written and strand the session via
/// fail-open. Consumed by the running batch budget in
/// `AgentLoop::handle_tool_calls`.
let checkpoint_reserve_tokens : Int = 16_384

///|
/// Whether the NEXT tool call in an executing batch provably fits:
/// measured usage, plus the batch's results recorded so far (actual
/// sizes, 1 char >= 1 token for mostly-ASCII tool output), plus one
/// worst-case result for the call about to run, plus the checkpoint
/// reserve, stays under the window. Checked before EVERY call at EVERY
/// usage level — this, not a pre-execution estimate, is what makes batch
/// execution safe: a pre-execution worst case over the whole batch would
/// false-positive constantly (any 4-call batch would trip it on a 256K
/// window at any usage), while the running check uses real sizes and only
/// pessimizes one call ahead.
fn AgentLoop::next_call_fits(
  self : Self,
  usage : @deepseek.Usage,
  spent_result_chars : Int64,
) -> Bool {
  let window = self.client.model.context_window().to_int64()
  usage.total_tokens.to_int64() +
  spent_result_chars +
  max_tool_result_chars.to_int64() +
  checkpoint_reserve_tokens.to_int64() <
  window
}

///|
/// Append the ceiling checkpoint: still-queued steers first, then the
/// Summary covering everything before them. Shared by both pressured
/// terminal shapes — the context yield and compact-on-finish.
///
/// The steers were already drained from the runtime queue, so they must be
/// persisted BEFORE the cancellable summary request — a cancellation mid-
/// request must find them durable, not lost (serve's turn-end drain would
/// see an empty queue and report nothing). The summary is generated from
/// the pre-steer snapshot (sessions are immutable values), so their content
/// cannot be folded into the checkpoint text; they stay verbatim past it,
/// projecting right after the summary to head the next turn.
///
/// Only summary GENERATION is fail-open: on a model/endpoint error the
/// session is returned uncompacted — a guardrail must not strand the turn —
/// and the next pressured step retries. The summary APPEND stays outside
/// the catch so a durability failure propagates like every other append.
/// Cancellation re-raises. The Bool reports whether a Summary was actually
/// appended, so callers never claim a checkpoint that does not exist.
async fn AgentLoop::checkpoint_at_ceiling(
  self : Self,
  session : @agent_session.Session,
  steers : ArrayView[@agent_runtime.SteerInput],
) -> (@agent_session.Session, Bool) {
  let to_sequence = session.last_sequence()
  // Warn-only invariant probe: every checkpoint site runs with its batch
  // closed, so the planner must confirm the full range as a boundary. A
  // clamp here means a sequencing bug let a checkpoint start mid-batch —
  // full-range coverage still swallows the batch whole, but the tail and
  // eviction policies this planner feeds must never inherit that state.
  if session.checkpoint_cut(requested_to=to_sequence) != Some(to_sequence) {
    @xlog.warn() <?
      { "event": "auto_compaction_cut_clamped", "to_sequence": to_sequence }
  }
  let covered = session
  let session = self.apply_steer_inputs(session, steers)
  @xlog.info() <?
    {
      "event": "auto_compaction_started",
      "from_sequence": 1,
      "to_sequence": to_sequence,
    }
  let summary = @compact.generate_compaction_summary(
    client=self.summary_client,
    covered,
  ) catch {
    error => {
      if @async.is_being_cancelled() || @async.is_cancellation_error(error) {
        raise error
      }
      @xlog.warn() <? { "event": "auto_compaction_failed", "error": "\{error}" }
      return (session, false)
    }
  }
  let item = session.summary_item(
    content=summary.content,
    from_sequence=1,
    to_sequence~,
  )
  let compacted = self.append(session, item)
  // Checkpoint output telemetry: the compacted projection measured at
  // checkpoint time. The surrounding shapes append suffixes afterwards
  // (late steers, kept answers, goal-check notices), so this is a LOWER
  // bound on the next request's seed — which keeps the warning's trigger
  // direction sound: a bound the suffixes only grow. The char proxy
  // itself overestimates tokens (a mostly-ASCII token spans several
  // chars), so crossing the window is NOT proven overflow — it means the
  // conservative accounting can no longer prove the next request fits,
  // and the event name says exactly that.
  let projection_chars = projected_chars(compacted)
  @xlog.info() <?
    {
      "event": "auto_compaction_finished",
      "from_sequence": 1,
      "to_sequence": to_sequence,
      "summary": summary.content,
      "usage": summary.usage,
      "duration_ms": summary.duration_ms,
      "compacted_projection_chars": projection_chars,
    }
  let window = self.client.model.context_window().to_int64()
  if projection_chars >= window {
    @xlog.warn() <?
      {
        "event": "auto_compaction_fit_unproven",
        "compacted_projection_chars": projection_chars,
        "context_window": window,
      }
  }
  (compacted, true)
}

///|
/// Every model-visible character of the session's projection: content,
/// reasoning, and tool-call names and arguments. A char proxy for what
/// the next request resends: tokens never exceed chars for mostly-ASCII
/// histories, so a projection whose chars fit provably fits, while one
/// whose chars do not fit is merely unproven.
fn projected_chars(session : @agent_session.Session) -> Int64 {
  let mut total : Int64 = 0
  for message in session.chat_messages() {
    total += message.content.length().to_int64()
    if message.reasoning_content is Some(reasoning) {
      total += reasoning.length().to_int64()
    }
    for call in message.tool_calls {
      total += call.name.length().to_int64() +
        call.arguments.length().to_int64()
    }
  }
  total
}

///|
/// End the turn at the context ceiling: the checkpoint, then the yield
/// terminal, in that order, so the turn's last event stays a terminal (the
/// session invariant every consumer of the raw log relies on) and the next
/// turn — chained by a controller, an armed goal, or the user — seeds from
/// the compacted projection.
///
/// The terminal is `Finished`: a distinct terminal kind would break old
/// readers (the session decoder is strict), and continuation machinery
/// chains finished turns. The `context_yield` event is the discriminator
/// for consumers that must not read a yield as task success.
async fn AgentLoop::yield_at_context_ceiling(
  self : Self,
  session : @agent_session.Session,
  steers : ArrayView[@agent_runtime.SteerInput],
) -> @agent_session.Session {
  // A goal(met) recorded in the turn's final batch defers its durable
  // [goal cleared] tombstone to a batch-safe boundary; every yield site
  // has the batch closed, and without this flush the tombstone would be
  // lost — current_goal() would resurrect a goal the model already met,
  // and auto-continue would keep chaining toward it.
  let session = self.flush_goal_tombstone(session)
  let to_sequence = session.last_sequence()
  let (session, compacted) = self.checkpoint_at_ceiling(session, steers)
  // The summary request takes seconds; steers submitted while it was in
  // flight are still preservable — drain again so they persist (uncovered,
  // after the summary) instead of being boundary-dropped at TurnDone.
  // (Compact-on-finish handles its own late steers by CONTINUING the turn
  // from the compacted projection — see finish_turn.)
  let session = self.apply_steer_inputs(session, self.runtime.pending_steers())
  self.finish_context_yield(session, to_sequence, compacted~)
}

///|
/// Seal a context yield: the `Finished` terminal for replay and chaining,
/// but `context_yield` — not `agent_finished` — on the wire, so live
/// consumers never read a mid-task ceiling yield as task success.
async fn AgentLoop::finish_context_yield(
  self : Self,
  session : @agent_session.Session,
  to_sequence : Int,
  compacted~ : Bool,
) -> @agent_session.Session {
  // Built FROM the shared prefix so the durable-log contract
  // (@agent_session.ContextYieldAnswerPrefix) can never drift from the
  // answer actually persisted — and honest about whether a checkpoint
  // actually exists (fail-open must not promise a summary that was never
  // appended).
  let answer = if compacted {
    @agent_session.ContextYieldAnswerPrefix +
    " This turn reached the model's context window and was checkpointed. " +
    "The work is not necessarily complete — continue it in a new turn, " +
    "which starts from the checkpoint summary."
  } else {
    @agent_session.ContextYieldAnswerPrefix +
    " This turn reached the model's context window; the checkpoint " +
    "attempt failed, so the turn ended uncompacted. Continue in a new " +
    "turn — its pressure retries the checkpoint."
  }
  let session = self.append(session, Terminal(Finished(answer)))
  // No push_finished_message: the yield status is not an assistant message
  // — the model-facing projection skips it too (the loop ends here, but the
  // buffer must never disagree with Session::chat_messages).
  @xlog.info() <?
    { "event": "context_yield", "to_sequence": to_sequence, "answer": answer }
  session
}
