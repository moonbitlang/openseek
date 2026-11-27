///|
/// What `/ultrareview [focus]` sends. It ends on `Focus:`, which the text typed
/// after the command completes. Kept word for word with Desktop's copy in
/// `desktop/frontend/composer_input.mbt`, so both front ends ask the agent for
/// the same review.
const UltrareviewPrompt : String =
  #|Review the changes on this branch with the bundled review swarm.
  #|
  #|1. Use git to find the merge base of HEAD with the default branch.
  #|2. Call the `mbtx` tool with `filename: "@builtin/review.mbtx"` and `args: ["--swarm", "--sha", <merge base>, "--", <criteria>]`. The criteria are the Focus text below or, when it is empty, "The changes since that base are correct, well-structured and tested."
  #|3. Wait for the job with `job_wait` and read it with `job_output`; a job that failed on a blocker still has its findings there. Report the merged findings: verified ones first, then unverified ones, then the refuted list.
  #|
  #|Focus:

///|
/// What `/simplify [focus]` sends. It ends on `Focus:`, which the text typed
/// after the command completes. Kept word for word with Desktop's copy in
/// `desktop/frontend/composer_input.mbt`.
const SimplifyPrompt : String =
  #|Sweep this repository for safe simplifications with the bundled simplify workflow.
  #|
  #|1. Call the `mbtx` tool with `filename: "@builtin/simplify.mbtx"` and `args: ["--", <focus>]`, where the focus is the Focus text below; when it is empty, pass no args.
  #|2. Wait for the job with `job_wait` and read it with `job_output`. If the sweep stops before starting (not at the repository root, uncommitted changes, HEAD not on the default branch, gh not signed in), report why and stop: do not commit, stash or push anything to get past it.
  #|3. Report the pull requests it opened, the changes the reviewers rejected, and the packages it skipped and why.
  #|
  #|Focus:

///|
/// Run a prompt command such as `/ultrareview [focus]`: start a turn whose
/// prompt is `prompt` followed by the typed `arguments`. The expanded prompt is
/// what the transcript shows, as a resumed session will show it too.
///
/// The command starts a turn of its own, so it runs only while the
/// conversation is idle. Steering it into a running turn would bury the
/// request in unrelated work, and a slash entry cannot be queued with Tab
/// (Tab completes the command name), so a busy conversation rejects it.
fn handle_prompt_command(
  state : State,
  name : String,
  prompt : String,
  arguments : String,
  cmds : Array[Cmd],
) -> Unit {
  guard state.run is Idle else {
    cmds.push(
      AppendItem(
        Error("/\{name} starts a new turn; run it when no task is running."),
      ),
    )
    return
  }
  let focus = arguments.trim()
  let text = if focus.is_empty() { prompt } else { "\{prompt} \{focus}" }
  start_prompt(state, text, cmds)
}

///|
test "ultrareview starts a turn with the review swarm prompt" {
  let state = drain_test_state()
  let cmds = update(
    state,
    UiInput(SlashCommand(name="ultrareview", arguments="")),
  )
  guard cmds is [AppendItem(Input(Prompt(shown))), StartAgent(text, ..)] else {
    fail("expected an echo and a started turn, got \{cmds.length()} commands")
  }
  assert_eq(text, UltrareviewPrompt)
  assert_eq(shown, text)
  // The contract the agent acts on, independent of the constant's wording.
  assert_true(text.contains("\"@builtin/review.mbtx\""))
  assert_true(text.contains("[\"--swarm\", \"--sha\", <merge base>, \"--\""))
  assert_true(state.run is Running(_))
}

///|
test "ultrareview appends the typed focus after the prompt" {
  let state = drain_test_state()
  let cmds = update(
    state,
    UiInput(SlashCommand(name="UltraReview", arguments="  the parser  ")),
  )
  guard cmds is [_, StartAgent(text, ..)] else {
    fail("expected a started turn")
  }
  assert_eq(text, "\{UltrareviewPrompt} the parser")
}

///|
test "simplify starts a turn with the simplify sweep prompt" {
  let state = drain_test_state()
  let cmds = update(
    state,
    UiInput(SlashCommand(name="simplify", arguments="openseek_tui")),
  )
  guard cmds is [AppendItem(Input(Prompt(shown))), StartAgent(text, ..)] else {
    fail("expected an echo and a started turn, got \{cmds.length()} commands")
  }
  assert_eq(text, "\{SimplifyPrompt} openseek_tui")
  assert_eq(shown, text)
  let busy = update(state, UiInput(SlashCommand(name="simplify", arguments="")))
  assert_eq(error_item_count(busy), 1)
}

///|
test "ultrareview is rejected while a turn runs" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("busy"))))
  let cmds = update(
    state,
    UiInput(SlashCommand(name="ultrareview", arguments="")),
  )
  assert_eq(error_item_count(cmds), 1)
  assert_eq(cmds.count_if(cmd => cmd is StartAgent(_, ..)), 0)
  assert_eq(state.pending_steers.length(), 0)
}

///|
test "prompt commands take multi-line focus text" {
  // Shift-Enter after `/ultrareview` starts a focus paragraph; the command must
  // opt in, or the UI sends that entry to the agent as a raw prompt.
  let takes_text = tui_slash_commands()
    .filter(spec => spec.multiline_arguments())
    .map(spec => spec.name())
  // A command that takes no text, like `/exit`, keeps a pasted `/exit` and a
  // newline an ordinary prompt.
  assert_eq(takes_text, ["ultrareview", "simplify"])
}
