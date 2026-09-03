///|
/// `openseek_tui` — the dedicated interactive terminal UI binary. It builds the
/// standalone TUI command (shared agent options plus UI-only options), parses
/// argv, and hands the parsed `Matches` to `@tui.run`. The headless engine is the
/// separate `openseek` binary, which this UI spawns per session (unless
/// overridden with `--engine`).
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("error: \{@cli.failure_message("\{error}")}\n") catch {
        _ => ()
      }
      @sys.exit(1)
    }
  }
}

///|
/// Parse the standalone `openseek_tui` command and run the UI. argparse owns
/// parsing, `--help`, and error reporting; `@tui.run` owns the preflight and the
/// terminal loop.
async fn run() -> Unit {
  let argv = @env.args()[1:]
  let env = @env.get_env_vars()
  let matches = @tui.cli_command(name="openseek_tui").parse(argv~, env~)
  @tui.run(matches)
}
