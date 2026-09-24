///|
/// What happens to a tool's permission question in this engine.
///
/// The knob is the engine's, never the controller's, which is what lets the
/// tool registry decide at BUILD time whether the escalation argument is
/// offered to the model at all.
pub enum ApprovalPolicy {
  Ask
  /// No channel is wired. Tools refuse actions needing approval, and mbtx
  /// omits its escalation argument. The stance for unattended runs.
  Never
  /// Grant without showing it to anyone, but still announced on the wire, so
  /// the transcript records what was auto-granted.
  Always
}

///|
/// Read the `--approval` value out of parsed arguments. `interactive` is
/// whether this subcommand has a controller that could answer — `serve` reads
/// commands from stdin, `run` does not — so asking where nobody can answer is
/// refused up front.
pub fn approval_policy(
  matches : @argparse.Matches,
  interactive~ : Bool,
) -> ApprovalPolicy raise {
  // Every subcommand that reads this declares the option with a default, so
  // an absent value is a command tree that forgot one — not a state a user
  // can reach.
  guard matches is { values: { "approval"? : Some([value, ..]), .. }, .. } else {
    return Never
  }
  match value.trim() {
    "ask" =>
      if interactive {
        Ask
      } else {
        fail(
          "--approval ask needs a controller to ask: this command reads no commands, so use never (refuse escalation) or always (grant it unasked)",
        )
      }
    "never" => Never
    "always" => Always
    other =>
      fail("unknown --approval value: \{other} (use ask, never, or always)")
  }
}
