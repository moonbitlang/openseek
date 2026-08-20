///|
/// Build the Skills page's independently updating Html. It re-renders when
/// its own state changes and when the focused host's library does, and at no
/// other time: everything else the model does — a streaming transcript, a
/// sidebar refresh — reuses the subtree already built.
///
/// The shell holds the `State` rather than the package: the page is one of
/// the shell's screens, opening it is a sidebar action the shell already
/// owns, and the library refresh a settled action asks for belongs to the
/// root's focused-host mirror. Everything drawn here comes from `State` and
/// `Input`, so nothing in the package can read the application model.
pub fn component(
  input : @rabbita.Val[Input],
  state : @rabbita.Val[State],
  emit : @cmd.Emit[Msg],
) -> @rabbita.Val[@html.Html] {
  state.view2(input, (state, input) => page(state, input, emit))
}
