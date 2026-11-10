///|
/// Run a one-shot command with an empty standard input, collecting stdout and
/// stderr separately. A Desktop GUI process on Windows may have no
/// standard-input handle to inherit; an empty input gives the child a valid
/// handle without allowing it to wait for input. Console-window suppression is
/// also unconditional because these commands are launched by the Desktop GUI
/// and never own an interactive console.
pub async fn collect_output_no_stdin(
  command : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  cwd? : StringView,
) -> @process.ProcessResult {
  @process.run(
    command,
    args,
    extra_env~,
    inherit_env~,
    stdin=Empty,
    stdout=Collect,
    stderr=Collect,
    cwd?,
    no_console_window=true,
  )
}
