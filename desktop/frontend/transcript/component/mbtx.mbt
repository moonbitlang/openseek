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
// Unlike the `plan` card this is not gated on the result: a snippet that
// compiled and then failed is exactly when its source matters, and for this
// tool `is_error` means the run failed, not that the arguments were refused.

///|
/// A recorded `mbtx` call, decoded for display.
priv struct MbtxCall {
  /// The `.mbtx` program, exactly as the model sent it.
  source : String
  /// The call's other scalar arguments, as `key: value` chip text.
  chips : Array[String]
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
    // The order the tool's README introduces current arguments in. Keep the
    // removed `run_in_background` last so transcripts recorded by older
    // versions remain readable; new calls never emit it.
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

///|
/// The failure stage a finished `mbtx` call reports, read from its brief —
/// the display-only caption the engine persists for renderers. The staged
/// wasm engine writes `mbtx (build failed, exit=N)` / `mbtx (build timeout)`
/// / `mbtx (build fault)` for build-phase failures and `mbtx (exit=N)` for a
/// program that built and then failed; transcripts recorded before staging
/// carry neither shape and keep the generic marker.
priv enum MbtxFailureStage {
  BuildError
  RuntimeError
}

///|
/// Whether the recorded call took the staged wasm path — the only path whose
/// `mbtx (exit=N)` brief is a RUN-stage claim. A single-shot target's one
/// exit code covers both stages (the engine's own tests pin that its report
/// claims neither), so those rows must keep the generic word. The target is
/// read from the call's own arguments; absent means the wasm default, and an
/// unreadable payload conservatively claims nothing.
fn mbtx_staged_target(arguments : String?) -> Bool {
  guard arguments is Some(arguments) else { return false }
  guard card_fields(arguments) is Some(fields) else { return false }
  match fields.get("target") {
    None | Some(String("wasm")) | Some(Null) => true
    _ => false
  }
}

///|
fn mbtx_failure_stage(
  name : String,
  brief : String?,
  is_error : Bool,
  arguments : String?,
) -> MbtxFailureStage? {
  guard is_error && name == "mbtx" && brief is Some(brief) else { return None }
  // The build shapes are unambiguous by construction: only the staged engine
  // writes them. The exit shape is a run-stage claim only where staging ran.
  if brief.has_prefix("mbtx (build") {
    Some(BuildError)
  } else if brief.has_prefix("mbtx (exit=") && mbtx_staged_target(arguments) {
    Some(RuntimeError)
  } else {
    None
  }
}

///|
/// The literal word beside a failed call's brief. An `mbtx` failure names its
/// STAGE: a build error is fixed in the source, a runtime error in the
/// program's behavior, and the row should say which before the card is even
/// opened. Every other failed call keeps the generic word.
fn failure_marker(
  name : String,
  brief : String?,
  is_error : Bool,
  arguments : String?,
) -> @html.Html? {
  guard is_error else { return None }
  match mbtx_failure_stage(name, brief, is_error, arguments) {
    Some(BuildError) =>
      Some(@html.span(class="tool-call-failed tool-stage-build", "build error"))
    Some(RuntimeError) =>
      Some(@html.span(class="tool-call-failed tool-stage-run", "runtime error"))
    None => Some(@html.span(class="tool-call-failed", "failed"))
  }
}
