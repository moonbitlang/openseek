///|
/// What happens to a tool's permission question in this engine.
///
/// The knob is the engine's, never the controller's, which is what lets the
/// tool registry decide at BUILD time whether the escalation argument is
/// offered to the model at all.
pub(all) enum ApprovalPolicy {
  Ask
  /// No channel is wired, so the tools that would ask do not offer the
  /// argument that asks. The stance for unattended runs.
  Never
  /// Grant without showing it to anyone, but still announced on the wire, so
  /// the transcript records what was auto-granted.
  Always
}

///|
/// Read the `--approval` value. `interactive` is whether this subcommand has a
/// controller that could answer — `serve` reads commands from stdin, `run`
/// does not — so asking where nobody can answer is refused up front.
fn parse_approval_policy(
  value : String,
  interactive~ : Bool,
) -> ApprovalPolicy raise {
  match value {
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

///|
/// The `--approval` option, defaulting to `never` on every subcommand,
/// `serve` included: only the controller knows whether it can answer, and the
/// engine cannot tell one attached to a human from a script reading its
/// stdout. Being asked is opt-in.
fn approval_option() -> @argparse.OptionArg {
  OptionArg(
    "approval",
    long="approval",
    env="OPENSEEK_APPROVAL",
    default_values=["never"],
    about="What happens when a tool asks permission to run without its sandbox: never (default; refuse without asking, and do not offer the argument to the model), ask (prompt the controller over the command stream and wait), always (grant without asking).",
  )
}

///|
/// Read the policy out of parsed arguments.
pub fn approval_policy(
  matches : @argparse.Matches,
  interactive~ : Bool,
) -> ApprovalPolicy raise {
  match matches {
    { values: { "approval"? : Some([value, ..]), .. }, .. } =>
      parse_approval_policy(value.trim().to_owned(), interactive~)
    // Every subcommand that reads this declares the option with a default, so
    // an absent value is a command tree that forgot one — not a state a user
    // can reach.
    _ => Never
  }
}
