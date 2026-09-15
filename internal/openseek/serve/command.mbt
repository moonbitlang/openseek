///|
/// `openseek serve` — the persistent JSONL command server the TUI drives: read
/// prompt/steer/cancel/compact/goal on stdin, stream events on stdout.
pub async fn run_serve_command(matches : @argparse.Matches) -> Unit {
  // Serve is ephemeral by default (durable only with --session); --no-session
  // makes that explicit and, as in every mode, contradicts an explicit --session.
  @options.reject_session_contradiction(matches)
  @execution.with_jsonl_stdout(() => {
    let workspace_root = @setup.prepare_workspace_root(
      matches,
      log_created=true,
    )
    run_serve(matches, workspace_root~)
  })
}
