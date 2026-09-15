///|
/// Start the headless CLI and report process-level failures. There is no
/// logger in this binary: nothing linked into it logs, so stdout carries only
/// the event stream or the command's own output.
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
