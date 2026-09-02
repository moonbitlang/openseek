///|
/// Whether a durable `runtime_notice` is text the engine wrote for the model
/// rather than news for the reader: the goal family (markers, the baseline
/// pairing record, reminders, checks) and the plan cadence's turn-boundary
/// reminder. Such text is durable transport, not something to card in the
/// transcript.
///
/// The live event path already drops these — `decode_engine_event` has no
/// `plan_reminder` case — and the durable path has to agree, or a model
/// instruction would surface as a notice card.
///
/// Local prefix check: this js-only package cannot depend on
/// `agent_session`'s constants.
fn is_model_directed_notice(content : String) -> Bool {
  content.has_prefix("[goal") || content.has_prefix("[plan reminder]")
}
