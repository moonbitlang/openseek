// The `mbtx` tool's arguments, read back out of the transcript.
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
// Unlike the `plan` card this is not gated on the result: source matters most
// when compilation or execution failed, and for this tool `is_error` normally
// describes that program lifecycle rather than refused arguments.

///|
/// A recorded `mbtx` call, decoded for display.
priv struct MbtxCall {
  /// The `.mbtx` program, exactly as the model sent it.
  source : String
  /// The call's other scalar arguments, as `key: value` chip text.
  chips : Array[String]
}

///|
/// The display treatment for a phase-aware MBTX failure. The tool's `brief`
/// is display-only metadata persisted with the result, so it is the stable
/// place to carry this distinction without scraping compiler prose or a panic
/// stack. Legacy background-build briefs are recognized too, so an existing
/// transcript gets the compile-time treatment after an app upgrade.
priv struct MbtxResultPresentation {
  summary : String
  output_label : String
  phase_label : String
  phase_class : String
  output_class : String
}

///|
/// Read the phase-aware MBTX result briefs introduced by structured compiler
/// diagnostics. `None` deliberately preserves the generic treatment for older
/// foreground `mbtx (exit=N)` results: those records never established which
/// phase failed, and the UI must not guess.
fn mbtx_result_presentation(brief : String?) -> MbtxResultPresentation? {
  guard brief is Some(brief) else { return None }
  if brief is ("mbtx (compile error)" | "mbtx (build failed)") {
    return Some({
      summary: "Compile-time error · mbtx",
      output_label: "Compiler diagnostics",
      phase_label: "compile time",
      phase_class: "compile-time",
      output_class: "mbtx-compiler-diagnostics",
    })
  }
  if brief is ("mbtx (compile timeout)" | "mbtx (build timeout)") {
    return Some({
      summary: "Compilation timed out · mbtx",
      output_label: "Compiler diagnostics",
      phase_label: "compile time",
      phase_class: "compile-time",
      output_class: "mbtx-compiler-diagnostics",
    })
  }
  let runtime_summary = if brief.has_prefix("mbtx (runtime error,") {
    Some("Runtime error · mbtx")
  } else {
    match brief {
      "mbtx (runtime timeout)" => Some("Runtime timed out · mbtx")
      "mbtx (runtime output limit)" => Some("Runtime stopped · mbtx")
      "mbtx (runtime sandbox denied)" => Some("Runtime blocked · mbtx")
      _ => None
    }
  }
  runtime_summary.map(summary => {
    summary,
    output_label: "Runtime output",
    phase_label: "runtime",
    phase_class: "runtime",
    output_class: "mbtx-runtime-output",
  })
}

///|
/// The literal phase badge shown beside a failed MBTX result. Its text carries
/// the distinction without depending on the compile/runtime colors.
fn mbtx_phase_badge(presentation : MbtxResultPresentation) -> @html.Html {
  @html.span(
    class="mbtx-phase-badge \{presentation.phase_class}",
    presentation.phase_label,
  )
}

///|
/// Decode recorded `mbtx` arguments, or `None` when they are not a call
/// this card can show: past the shared payload bound, not JSON, not an object,
/// or carrying no program to display.
///
/// Deliberately more permissive than the tool's own decoder — it does not
/// re-check the target name, or that `warning` is `on`/`off`. Whether the call
/// was accepted is the paired result, not a rule re-implemented here, and a
/// second copy of the validation would only drift from the one that matters.
/// An argument with an unexpected value therefore still shows, as its own
/// chip, which is what a reader looking at a rejected call needs to see.
fn decode_mbtx_call(arguments : String) -> MbtxCall? {
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
  Some({ source, chips, })
}

///|
/// The program view for a `mbtx` tool call: the source it asked to run,
/// verbatim and line-numbered, under a row of chips for the arguments that
/// shaped the run. `None` when the payload is not a readable call, which keeps
/// the generic JSON rendering.
///
/// The numbers exist to be matched against the paired result, whose compiler
/// diagnostics cite `line:column` positions into this source. That is also why
/// the source skips `truncate_output`: its clamp would misnumber every line
/// after its skip marker. Cost stays bounded without it — `card_fields`
/// refuses payloads past the shared card ceiling, and the numbered renderer
/// clamps a degenerate line count itself, keeping true numbers on the tail.
fn mbtx_card(arguments : String) -> @html.Html? {
  guard decode_mbtx_call(arguments) is Some(call) else { return None }
  Some(
    @html.div(class="mbtx-args", [
      chip_row(call.chips),
      @html.pre(class="moonbit-source", [
        @syntax_html.moonbit_numbered_source(call.source),
      ]),
    ]),
  )
}
