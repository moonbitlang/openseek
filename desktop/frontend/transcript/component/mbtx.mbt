// The `mbtx` tool's arguments, read back out of the transcript.
//
// A call to it is a whole `.mbtx` program, and the generic arguments rendering
// shows the recorded JSON: the program arrives as one long line with every
// newline spelled `\n`, so the one field a reader came for is the one field
// they cannot read. The card below lifts `source` out as verbatim program text
// and states the call's remaining arguments as chips above it. Saved-script
// calls display the filename as plain text in their own Filename view.
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
priv enum MbtxProgram {
  Source(String)
  Filename(String)
  Save(String, String)
}

///|
/// A recorded `mbtx` call, decoded for display.
priv struct MbtxCall {
  program : MbtxProgram
  /// The call's other scalar arguments, as `key: value` chip text.
  chips : Array[String]
}

///|
/// Decode recorded `mbtx` arguments, or `None` when they are not a call
/// this card can show: past the shared payload bound, not JSON, not an object,
/// or carrying no unambiguous program to display.
///
/// Deliberately more permissive than the tool's own decoder — it does not
/// re-check the target name, or that `warning` is `on`/`off`. Whether the call
/// was accepted is the paired result, not a rule re-implemented here, and a
/// second copy of the validation would only drift from the one that matters.
/// An argument with an unexpected value therefore still shows, as its own
/// chip, which is what a reader looking at a rejected call needs to see.
fn decode_mbtx_call(arguments : String) -> MbtxCall? {
  guard card_fields(arguments) is Some(fields) else { return None }
  let program = match (fields.get("source"), fields.get("filename")) {
    (Some(String(source)), None) if !source.is_blank() => Source(source)
    (None, Some(String(filename))) if !filename.is_blank() => Filename(filename)
    (Some(String(source)), Some(String(filename))) if !source.is_blank() &&
      !filename.is_blank() => Save(source, filename)
    _ => return None
  }
  let chips = scalar_chips(
    fields,
    // The order the tool's README introduces current arguments in. Keep the
    // removed `run_in_background` last so transcripts recorded by older
    // versions remain readable; new calls never emit it.
    known=["target", "cwd", "escalated", "warning", "run_in_background"],
    dramatized=["source", "filename"],
  )
  Some({ program, chips, })
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
fn mbtx_card(arguments : String) -> (String, @html.Html)? {
  guard decode_mbtx_call(arguments) is Some(call) else { return None }
  let (label, content) = match call.program {
    Save(source, filename) =>
      (
        "Save & run",
        @html.div([
          @html.pre(class="tool-card-original-json", filename),
          @html.pre(class="moonbit-source", [
            @syntax_html.moonbit_numbered_source(source),
          ]),
        ]),
      )
    Source(source) =>
      (
        "Source",
        @html.pre(class="moonbit-source", [
          @syntax_html.moonbit_numbered_source(source),
        ]),
      )
    Filename(filename) =>
      ("Filename", @html.pre(class="tool-card-original-json", filename))
  }
  Some((label, @html.div(class="mbtx-args", [chip_row(call.chips), content])))
}

///|
/// The engine names the phase in failed staged runs; status and exit codes
/// belong to the outcome and output, respectively. Single-shot targets do
/// not claim a phase.
priv enum MbtxFailureStage {
  BuildError
  RuntimeError
}

///|
fn mbtx_failure_stage(
  name : String,
  brief : String?,
  is_error : Bool,
) -> MbtxFailureStage? {
  guard is_error && name == "mbtx" else { return None }
  match brief {
    Some("mbtx build") => Some(BuildError)
    Some("mbtx run") => Some(RuntimeError)
    _ => None
  }
}

///|
/// Result rows name the failure stage, since parallel calls can separate them
/// from their requests. Without recorded arguments, the result's label is its
/// brief, which already names build failures. mbtx request rows use their
/// status icon instead.
fn failure_marker(
  name : String,
  brief : String?,
  is_error : Bool,
  arguments : String?,
) -> @html.Html? {
  guard is_error else { return None }
  match mbtx_failure_stage(name, brief, is_error) {
    Some(BuildError) if arguments is None => None
    Some(BuildError) =>
      Some(@html.span(class="tool-call-failed tool-stage-build", "build error"))
    Some(RuntimeError) =>
      Some(@html.span(class="tool-call-failed tool-stage-run", "runtime error"))
    None => Some(@html.span(class="tool-call-failed", "failed"))
  }
}

///|
/// The stage modifier for a failed row's container class: build failures read
/// amber (the fix lives in the source), runtime failures keep the error red.
fn failure_stage_class(
  name : String,
  brief : String?,
  is_error : Bool,
) -> String {
  match mbtx_failure_stage(name, brief, is_error) {
    Some(BuildError) => " stage-build"
    Some(RuntimeError) | None => ""
  }
}
