// The `run_moonbit` tool's arguments, read back out of the transcript.
//
// A call to it is a whole `.mbtx` program, and the generic arguments rendering
// shows the recorded JSON: the program arrives as one long line with every
// newline spelled `\n`, so the one field a reader came for is the one field
// they cannot read. The card below lifts `source` out as verbatim program text
// and states the call's remaining arguments as chips above it.
//
// Nothing is hidden by that: the payload as the model actually sent it stays a
// click away in the neighboring Original JSON tab. So the card is free to show
// only what it can state plainly — an argument it cannot chip (a nested value,
// which this tool's schema has none of) is left to the original.
//
// Unlike the `plan` card this is not gated on the result: a snippet that
// compiled and then failed is exactly when its source matters, and for this
// tool `is_error` means the run failed, not that the arguments were refused.

///|
/// A recorded `run_moonbit` call, decoded for display.
priv struct RunMoonbitCall {
  /// The `.mbtx` program, exactly as the model sent it.
  source : String
  /// The call's other scalar arguments, as `key: value` chip text.
  chips : Array[String]
}

///|
/// Decode recorded `run_moonbit` arguments, or `None` when they are not a call
/// this card can show: past the shared payload bound, not JSON, not an object,
/// or carrying no program to display.
///
/// Deliberately more permissive than the tool's own decoder — it does not
/// re-check the target name, or that `warning` is `on`/`off`. Whether the call
/// was accepted is the paired result, not a rule re-implemented here, and a
/// second copy of the validation would only drift from the one that matters.
/// An argument with an unexpected value therefore still shows, as its own
/// chip, which is what a reader looking at a rejected call needs to see.
fn decode_run_moonbit(arguments : String) -> RunMoonbitCall? {
  guard card_fields(arguments) is Some(fields) &&
    fields.get("source") is Some(String(source)) &&
    !source.is_blank() else {
    return None
  }
  let chips = scalar_chips(
    fields,
    // The order the tool's README introduces them in.
    known=["target", "cwd", "escalated", "warning", "run_in_background"],
    dramatized=["source"],
  )
  Some({ source, chips })
}

///|
/// The program view for a `run_moonbit` tool call: the source it asked to run,
/// verbatim, under a row of chips for the arguments that shaped the run.
/// `None` when the payload is not a readable call, which keeps the generic
/// JSON rendering.
fn run_moonbit_card(arguments : String) -> @html.Html? {
  guard decode_run_moonbit(arguments) is Some(call) else { return None }
  Some(
    @html.div(class="run-moonbit-args", [
      chip_row(call.chips),
      @html.pre(class="run-moonbit-source", [
        @syntax_html.moonbit_source_code(truncate_output(call.source)),
      ]),
    ]),
  )
}
