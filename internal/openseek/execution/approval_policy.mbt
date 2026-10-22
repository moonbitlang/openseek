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
  /// A reviewer subagent decides each question against the user's own
  /// words. What it cannot settle (it escalates, times out, or never
  /// reports) goes to the controller when `ask_on_escalate`, and is refused
  /// otherwise — `run` reads no commands, so there is nobody to escalate to.
  Review(ask_on_escalate~ : Bool)
}

///|
/// Read the `--approval` value out of parsed arguments. `interactive` is
/// whether this subcommand has a controller that could answer — `serve` reads
/// commands from stdin, `run` does not — so asking where nobody can answer is
/// refused up front.
///
/// A `delegated` run (launched by a parent, `--cancel-on-stdin-eof`) has
/// nobody to ask, and a parent's standing grant must not reach the children it
/// delegates to: it is always `Never`, whatever `OPENSEEK_APPROVAL` it
/// inherited, and an explicit `--approval` other than `never` is refused.
pub fn approval_policy(
  matches : @argparse.Matches,
  interactive~ : Bool,
  delegated~ : Bool = false,
) -> ApprovalPolicy raise {
  // Every subcommand that reads this declares the option with a default, so
  // an absent value is a command tree that forgot one — not a state a user
  // can reach.
  guard matches is { values: { "approval"? : Some([value, ..]), .. }, .. } else {
    return Never
  }
  if delegated {
    guard !(matches.sources.get("approval") is Some(Argv)) ||
      value.trim() == "never" else {
      fail(
        "a delegated run (--cancel-on-stdin-eof) refuses every escalation: --approval must be never",
      )
    }
    return Never
  }
  match value.trim() {
    "ask" =>
      if interactive {
        Ask
      } else {
        fail(
          "--approval ask needs a controller to ask: this command reads no commands, so use never (refuse escalation), always (grant it unasked), or review (a reviewer decides; what it cannot settle is refused)",
        )
      }
    "never" => Never
    "always" => Always
    "review" => Review(ask_on_escalate=interactive)
    other =>
      fail(
        "unknown --approval value: \{other} (use ask, never, always, or review)",
      )
  }
}
