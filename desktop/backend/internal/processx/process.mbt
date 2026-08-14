///|
/// Run a one-shot command whose standard input is already at EOF, collecting
/// stdout and stderr separately. A Desktop GUI process on Windows may have no
/// standard-input handle to inherit; passing the read end of a closed pipe
/// gives the child a valid handle without allowing it to wait for input.
/// Console-window suppression is also unconditional because these commands
/// are launched by the Desktop GUI and never own an interactive console.
pub async fn collect_output_no_stdin(
  command : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  cwd? : StringView,
) -> (Int, &@io.Data, &@io.Data) {
  let (stdin_reader, stdin_writer) = @process.write_to_process()
  stdin_writer.close()
  @process.collect_output(
    command,
    args,
    extra_env~,
    inherit_env~,
    stdin=stdin_reader,
    cwd?,
    no_console_window=true,
  )
}
