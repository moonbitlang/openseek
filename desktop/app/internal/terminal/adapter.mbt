///|
pub using @shared {
  type TerminalState,
  type TerminalPush,
  type TerminalError,
  ack_terminal,
  close_all_terminals,
  close_terminal,
  open_terminal,
  resize_terminal,
  run_terminal_pump,
  write_terminal,
}

///|
pub fn new_terminal_state() -> TerminalState {
  @shared.new_terminal_state(runtime=@host_runtime.native())
}
