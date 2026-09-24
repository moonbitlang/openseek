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
    about="What happens when a tool needs permission (sandbox escalation or file deletion): never (default; refuse without asking), ask (prompt the controller over the command stream and wait), always (grant without asking).",
  )
}
