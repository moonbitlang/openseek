///|
/// Fake host implementation for the first Pattern Repair protocol slice. It
/// deliberately does not invoke an Agent or moongrep yet.
fn pattern_repair_op(
  payload : @protocol.PatternRepairPayload,
) -> @protocol.PatternRepairReply {
  {
    root: payload.root,
    generation: payload.generation,
    pattern: payload.pattern,
    success: true,
    message: "Pattern repair host prototype accepted the pattern.",
  }
}
