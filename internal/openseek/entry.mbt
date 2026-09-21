///|
/// Run either CLI entry point with the same diagnostics and exit status.
pub async fn run_cli() -> Unit {
  dispatch() catch {
    error => {
      @stdio.stderr.write("error: \{@cli.failure_message("\{error}")}\n") catch {
        _ => ()
      }
      @sys.exit(1)
    }
  }
}
