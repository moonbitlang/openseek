///|
/// Start the headless CLI and report process-level failures.
async fn main {
  @app.dispatch() catch {
    error => {
      @stdio.stderr.write("error: \{@cli.failure_message("\{error}")}\n") catch {
        _ => ()
      }
      @sys.exit(1)
    }
  }
}
