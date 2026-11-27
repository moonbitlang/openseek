///|
priv struct CompletionMenu {
  key : String
  items : Array[@completion.CompletionItem]
}

///|
/// Mutable state backing the input-completion menu: `key` identifies the
/// current menu context (so the selection resets when it changes), `selected`
/// is the highlighted item index, and `dismissed` records an Esc dismissal.
priv struct CompletionState {
  mut key : String
  mut selected : Int32
  mut dismissed : Bool
}

///|
fn CompletionState::CompletionState() -> CompletionState {
  { key: "", selected: 0, dismissed: false, }
}

///|
/// Forget the current menu context, clearing the selection and any dismissal.
fn CompletionState::reset(self : CompletionState) -> Unit {
  self.key = ""
  self.selected = 0
  self.dismissed = false
}

///|
/// The composer's text when it holds a single-line entry in input mode — the
/// precondition shared by completion, slash-command parsing, and slash-entry
/// detection. None in shell mode or for multi-line input, neither of which is a
/// slash context.
fn single_line_input_text(composer : @composer.Model) -> String? {
  guard composer.mode().is_input() else { return None }
  let text = composer.text()
  guard !text.contains("\n") else { return None }
  Some(text)
}

///|
fn completion_menu_for_composer(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
) -> CompletionMenu? {
  guard single_line_input_text(composer) is Some(text) else { return None }
  guard text.strip_prefix("/") is Some(rest) else { return None }
  let rest = rest.to_owned()
  // A doubled leading slash (`//`, `//e`) is not a command-name prefix: the
  // filter would otherwise match a command by its `/`-prefixed display label
  // (e.g. `/` matches `/exit`), so reject it rather than show a menu.
  if rest.has_prefix("/") {
    return None
  }
  // Complete the command name from the configured set. Past the command name
  // there is nothing to complete: the configured commands take no arguments.
  if @slash.has_arguments(rest) {
    return None
  }
  if commands.is_empty() {
    return None
  }
  Some({
    key: "command:\{rest.to_lower()}",
    items: @completion.completion_item_matches(
      commands.completion_items(),
      rest,
    ),
  })
}

///|
/// The slash command syntactically present in the composer, if any.
///
/// Returns None when no slash commands are configured, so a consumer that has
/// not opted into the feature keeps submitting `/`-prefixed lines as ordinary
/// input. When the feature is enabled, parsing is independent of whether the
/// specific name is registered — an unknown command still dispatches so the
/// handler reports it rather than the agent receiving it as a prompt or it
/// being swallowed as a no-completion notice.
fn slash_command_invocation_for_composer(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
) -> @slash.SlashCommandInvocation? {
  if commands.is_empty() {
    return None
  }
  match single_line_input_text(composer) {
    Some(text) => @slash.SlashCommandInvocation::parse(text)
    None => registered_multiline_invocation(commands, composer)
  }
}

///|
/// A multi-line entry whose first word names a configured command, such as
/// `/ultrareview` followed by Shift-Enter and a focus paragraph. Its arguments
/// keep their line breaks. Only a registered name counts, so a multi-line
/// prompt that merely begins with a path (`/usr/lib/...`) stays a prompt.
fn registered_multiline_invocation(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
) -> @slash.SlashCommandInvocation? {
  guard composer.mode().is_input() else { return None }
  guard @slash.SlashCommandInvocation::parse(composer.text())
    is Some(invocation) &&
    commands.get(invocation.name()) is Some(_) else {
    return None
  }
  Some(invocation)
}

///|
fn Ui::completion_menu(self : Self) -> CompletionMenu? {
  completion_menu_for_composer(self.config.slash_commands, self.composer)
}

///|
fn Ui::sync_completion_menu(self : Self) -> Unit {
  match self.completion_menu() {
    Some(menu) => {
      if menu.key != self.completion.key {
        self.completion.key = menu.key
        self.completion.selected = 0
      }
      if menu.items.length() == 0 {
        self.completion.selected = 0
      } else if self.completion.selected >= menu.items.length() {
        self.completion.selected = menu.items.length() - 1
      }
    }
    None => self.completion.reset()
  }
}

///|
/// Whether the terminal is tall enough to draw the completion menu. A menu that
/// cannot be rendered must not capture keys, so this gates `completion_menu_open`
/// (and the Enter decision) on the same row budget the renderer uses.
fn Ui::completion_menu_visible(self : Self) -> Bool {
  guard self.viewport is Some(viewport) else { return true }
  @render.completion_menu_fits(max_rows=viewport.rows())
}

///|
fn Ui::completion_menu_open(self : Self) -> Bool {
  !self.completion.dismissed &&
  self.completion_menu_visible() &&
  self.completion_menu() is Some(_)
}

///|
async fn Ui::redraw_after_completion_selection(self : Self) -> Unit {
  self.notice = None
  self.redraw()
}

///|
async fn Ui::move_completion_selection(self : Self, delta : Int32) -> Unit {
  let len = match self.completion_menu() {
    Some(menu) => menu.items.length()
    None => 0
  }
  if len > 0 {
    if delta < 0 {
      self.completion.selected = if self.completion.selected <= 0 {
        len - 1
      } else {
        self.completion.selected - 1
      }
    } else {
      self.completion.selected = if self.completion.selected + 1 >= len {
        0
      } else {
        self.completion.selected + 1
      }
    }
  }
  self.redraw_after_completion_selection()
}

///|
/// The canonical `/name arguments` text for a dispatched slash command, used
/// for history so recall repeats what actually ran rather than the half-typed
/// prefix in the composer.
fn slash_command_text(name~ : String, arguments~ : String) -> String {
  if arguments.is_empty() {
    "/\{name}"
  } else {
    "/\{name} \{arguments}"
  }
}

///|
async fn Ui::submit_slash_command(
  self : Self,
  name~ : String,
  arguments~ : String,
) -> Event? {
  // Record what ran, not `composer.text()`: accepting a completion can dispatch
  // arguments that differ from the typed prefix, and recalling the prefix would
  // re-select the first match and run a different command.
  let text = slash_command_text(name~, arguments~)
  self.history.push(Entry(text, self.composer.mode()))
  // Mid-flight until the app's queue receives the event (the redraw below
  // awaits); see `pending_submissions`.
  self.pending_submissions += 1
  self.composer.reset()
  self.history.reset_navigation()
  self.notice = None
  self.completion.reset()
  self.redraw()
  Some(SlashCommand(name~, arguments~))
}

///|
/// The composer text that accepting the highlighted menu item produces: a
/// completed command name (`/comp` → `/compact`). None when the menu is empty
/// (e.g. an unknown command), so there is nothing to accept. The candidates are
/// command names from the configured spec — trusted text, so no sanitization is
/// needed here.
fn completion_acceptance_text(
  menu : CompletionMenu,
  selected : Int32,
) -> String? {
  guard menu.items.get(selected) is Some(item) else { return None }
  Some("/\{item.insert_text()}")
}

///|
/// Accept the highlighted completion into the composer without submitting; Tab
/// completes the text where Enter would submit it.
async fn Ui::accept_completion(self : Self) -> Event? {
  guard self.completion_menu() is Some(menu) else { return None }
  guard completion_acceptance_text(menu, self.completion.selected) is Some(text) else {
    return None
  }
  self.composer.replace(text, mode=self.composer.mode())
  self.redraw_after_text_change()
  None
}

///|
/// Whether the composer holds a slash-command entry: the feature is enabled and
/// either the single-line input begins with `/`, or a multi-line input begins
/// with a configured command name. Such an entry is completed or dispatched on
/// Enter, never queued as a prompt — not even a lone `/`, which is not yet a
/// valid invocation but must not be queued as literal text.
fn composer_is_slash_entry(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
) -> Bool {
  if commands.is_empty() {
    return false
  }
  match single_line_input_text(composer) {
    Some(text) => text.has_prefix("/")
    None => registered_multiline_invocation(commands, composer) is Some(_)
  }
}

///|
/// What pressing Enter in the composer should do, decided purely from the
/// command set, the composer text, and the menu state.
priv enum EnterDecision {
  /// Dispatch a slash command with these arguments.
  RunSlashCommand(name~ : String, arguments~ : String)
  /// Submit the composer text as ordinary input (prompt or shell command).
  SubmitInput
  /// The menu is open but nothing matches; show a notice and do nothing.
  NoCompletionMatch
}

///|
/// Decide what Enter does. Accepting a highlighted command name dispatches it
/// with no arguments — the handler runs it or rejects it. An unknown command
/// still dispatches so the handler can reject it, and anything else is submitted
/// as ordinary input.
///
/// `menu_visible` is false when the terminal is too short to draw the menu, in
/// which case it must not influence the decision even though it is logically
/// open.
fn ui_enter_decision(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
  completion : CompletionState,
  menu_visible~ : Bool,
) -> EnterDecision {
  let menu = if completion.dismissed || !menu_visible {
    None
  } else {
    completion_menu_for_composer(commands, composer)
  }
  let invocation = slash_command_invocation_for_composer(commands, composer)
  guard menu is Some(menu) else {
    return match invocation {
      Some(inv) => RunSlashCommand(name=inv.name(), arguments=inv.arguments())
      // No menu and nothing to dispatch. A slash entry that does not parse into
      // a command (a lone `/`, `/ `, after the menu was dismissed or is too
      // short to draw) must not be submitted as a prompt — that would leak
      // malformed slash input into the agent conversation. Leave it as a
      // no-match instead; only genuine non-slash input is submitted.
      None =>
        if composer_is_slash_entry(commands, composer) {
          NoCompletionMatch
        } else {
          SubmitInput
        }
    }
  }
  // Require a typed command name before accepting the highlighted item. A bare
  // `/` opens a menu of every command with index 0 highlighted, and Enter there
  // must not silently run the first one (e.g. `/exit`, quitting the app) — it is
  // an unfinished entry, not a chosen command.
  guard invocation is Some(invocation) else { return NoCompletionMatch }
  // Command-name menu: accept the highlighted command and dispatch it with no
  // arguments (the only commands take none); the handler runs or rejects it.
  match menu.items.get(completion.selected) {
    Some(item) => RunSlashCommand(name=item.insert_text(), arguments="")
    // Nothing matches the typed name: dispatch it (an unknown command) so the
    // handler can reject it instead of swallowing it as a notice.
    None =>
      RunSlashCommand(name=invocation.name(), arguments=invocation.arguments())
  }
}

///|
fn command_specs() -> Array[@slash.SlashCommandSpec] {
  [
    SlashCommandSpec(name="exit", description="exit the TUI"),
    SlashCommandSpec(name="compact", description="compact the conversation"),
  ]
}

///|
fn composer_with(text : String) -> @composer.Model {
  let composer = @composer.Model("")
  composer.insert_user_text(text)
  composer
}

///|
test "submitted input marks prompt and shell command" {
  let input = @composer.Model("")
  let shell = @composer.Model("")
  shell.insert_user_text("!")
  assert_true(submitted_input("hello", input.mode()) == Prompt("hello"))
  assert_true(submitted_input("pwd ", shell.mode()) == Command("pwd"))
  assert_true(submitted_input("", shell.mode()) == Command(""))
}

///|
test "completion menu only opens for single-line slash input contexts" {
  let slash = @composer.Model("")
  slash.insert_user_text("/co")
  guard completion_menu_for_composer(command_specs(), slash)
    is Some(command_menu) else {
    fail("expected command completion menu")
  }
  assert_eq(command_menu.key, "command:co")
  assert_eq(command_menu.items.length(), 1)
  assert_eq(command_menu.items[0].label(), "/compact")
  let plain = @composer.Model("")
  plain.insert_user_text("co")
  assert_true(completion_menu_for_composer(command_specs(), plain) is None)
  // Past the command name there is nothing to complete: the configured commands
  // take no arguments, so a separator closes the menu.
  let spaced = @composer.Model("")
  spaced.insert_user_text("/compact now")
  assert_true(completion_menu_for_composer(command_specs(), spaced) is None)
  // Multi-line input never opens a menu.
  let multiline = @composer.Model("")
  multiline.insert_user_text("/compact\n")
  assert_true(completion_menu_for_composer(command_specs(), multiline) is None)
}

///|
test "enter dispatches the accepted command name with no arguments" {
  // Typing `/compact` (exact) or `/comp` (partial) and pressing Enter dispatches
  // `compact` with empty args; the handler runs it.
  for typed in ["/compact", "/comp"] {
    guard ui_enter_decision(
        command_specs(),
        composer_with(typed),
        CompletionState(),
        menu_visible=true,
      )
      is RunSlashCommand(name~, arguments~) else {
      fail("expected \{typed} to dispatch the compact command")
    }
    assert_eq(name, "compact")
    assert_eq(arguments, "")
  }
}

///|
test "a multi-line entry dispatches only a registered command" {
  let specs = command_specs()
  guard ui_enter_decision(
      specs,
      composer_with("/compact\nfirst line\nsecond line"),
      CompletionState(),
      menu_visible=true,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected the multi-line /compact entry to dispatch")
  }
  assert_eq(name, "compact")
  assert_eq(arguments, "first line\nsecond line")
  assert_true(composer_is_slash_entry(specs, composer_with("/compact\nfocus")))
  // A multi-line prompt that only starts with a slash is still a prompt.
  let path = composer_with("/usr/lib/libfoo.so is missing\nwhy?")
  assert_true(
    ui_enter_decision(specs, path, CompletionState(), menu_visible=true)
    is SubmitInput,
  )
  assert_true(!composer_is_slash_entry(specs, path))
}

///|
test "enter dispatches a command with typed arguments verbatim" {
  // Past the command name there is no menu; the typed invocation dispatches as-is
  // (here the handler will reject the argument, but the decision still routes it).
  guard ui_enter_decision(
      command_specs(),
      composer_with("/compact extra"),
      CompletionState(),
      menu_visible=true,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected /compact to dispatch with the typed arguments")
  }
  assert_eq(name, "compact")
  assert_eq(arguments, "extra")
}

///|
test "accepted slash completion is recorded so recall re-runs it" {
  // Accepting `/comp` dispatches `compact`; history stores the canonical command
  // (via `slash_command_text`) so recall repeats it rather than the typed prefix.
  assert_eq(slash_command_text(name="compact", arguments=""), "/compact")
  assert_eq(slash_command_text(name="exit", arguments="now"), "/exit now")
  guard ui_enter_decision(
      command_specs(),
      composer_with("/comp"),
      CompletionState(),
      menu_visible=true,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected the completed command to run")
  }
  assert_eq(name, "compact")
  assert_eq(arguments, "")
}

///|
test "enter ignores the completion menu when it cannot be rendered" {
  // Menu hidden (terminal too short): the typed prefix dispatches as-is rather
  // than silently accepting the highlighted command.
  guard ui_enter_decision(
      command_specs(),
      composer_with("/comp"),
      CompletionState(),
      menu_visible=false,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected the typed prefix to dispatch when the menu is hidden")
  }
  assert_eq(name, "comp")
  assert_eq(arguments, "")
  // Visible, the same input accepts the highlighted command instead.
  guard ui_enter_decision(
      command_specs(),
      composer_with("/comp"),
      CompletionState(),
      menu_visible=true,
    )
    is RunSlashCommand(name=completed, ..) else {
    fail("expected the visible menu to complete the command")
  }
  assert_eq(completed, "compact")
}

///|
test "a malformed slash entry is not submitted as a prompt" {
  let specs = command_specs()
  // Menu dismissed (Esc): a lone `/` or `/ ` parses to no command, but must not
  // be submitted — that would leak the raw slash text into the agent.
  let dismissed = CompletionState::CompletionState()
  dismissed.dismissed = true
  for typed in ["/", "/ "] {
    assert_true(
      ui_enter_decision(
        specs,
        composer_with(typed),
        dismissed,
        menu_visible=true,
      )
      is NoCompletionMatch,
    )
  }
  // Same protection when the terminal is too short to draw the menu.
  assert_true(
    ui_enter_decision(
      specs,
      composer_with("/"),
      CompletionState(),
      menu_visible=false,
    )
    is NoCompletionMatch,
  )
  // Ordinary (non-slash) input is still submitted normally.
  assert_true(
    ui_enter_decision(
      specs,
      composer_with("hello"),
      dismissed,
      menu_visible=true,
    )
    is SubmitInput,
  )
}

///|
test "enter on a bare or doubled slash does not run the first command" {
  // A bare `/` opens a menu of every command with index 0 highlighted, and a
  // doubled `//`/`//e` would otherwise match a command by its `/`-prefixed
  // label. Enter must treat both as unfinished entries, not silently run the
  // first command (`/exit` is registered first, so this would quit the app).
  for typed in ["/", "//", "//e"] {
    assert_true(
      ui_enter_decision(
        command_specs(),
        composer_with(typed),
        CompletionState(),
        menu_visible=true,
      )
      is NoCompletionMatch,
    )
  }
  // No completion menu is offered for a doubled slash either.
  assert_true(
    completion_menu_for_composer(command_specs(), composer_with("//")) is None,
  )
}

///|
test "enter submits ordinary input outside a slash context" {
  assert_true(
    ui_enter_decision(
      command_specs(),
      composer_with("hello world"),
      CompletionState(),
      menu_visible=true,
    )
    is SubmitInput,
  )
}

///|
test "tab completes a command name" {
  // `/comp` completes to the highlighted command name.
  guard completion_menu_for_composer(command_specs(), composer_with("/comp"))
    is Some(name_menu) else {
    fail("expected command menu")
  }
  assert_true(completion_acceptance_text(name_menu, 0) is Some("/compact"))
  // A bare `/` completes to the first command, never queuing the slash.
  guard completion_menu_for_composer(command_specs(), composer_with("/"))
    is Some(all_menu) else {
    fail("expected command menu for bare slash")
  }
  assert_true(completion_acceptance_text(all_menu, 0) is Some("/exit"))
  // An unknown command has no item to accept.
  guard completion_menu_for_composer(command_specs(), composer_with("/nope"))
    is Some(empty_menu) else {
    fail("expected an (empty) command menu")
  }
  assert_true(completion_acceptance_text(empty_menu, 0) is None)
}

///|
test "a slash-command line is never queued as a prompt" {
  let specs = command_specs()
  // Both a partial command and a lone `/` are slash entries (not queued).
  assert_true(composer_is_slash_entry(specs, composer_with("/comp")))
  assert_true(composer_is_slash_entry(specs, composer_with("/")))
  // Ordinary text is not.
  assert_false(composer_is_slash_entry(specs, composer_with("hello")))
  // Multi-line input is a slash entry only when it names a registered command.
  assert_true(composer_is_slash_entry(specs, composer_with("/compact\nx")))
  assert_false(composer_is_slash_entry(specs, composer_with("/path\nx")))
  // With the feature disabled, a slash line is ordinary input (queueable).
  let no_commands : @slash.SlashCommands = []
  assert_false(composer_is_slash_entry(no_commands, composer_with("/path")))
}

///|
test "slash command invocation parses any single-line slash entry" {
  let specs = command_specs()
  let with_args = @composer.Model("")
  with_args.insert_user_text("/compact now")
  guard slash_command_invocation_for_composer(specs, with_args)
    is Some(invocation) else {
    fail("expected compact slash invocation")
  }
  assert_eq(invocation.name(), "compact")
  assert_eq(invocation.arguments(), "now")
  let trailing_space = @composer.Model("")
  trailing_space.insert_user_text("/compact   ")
  guard slash_command_invocation_for_composer(specs, trailing_space)
    is Some(invocation) else {
    fail("expected compact slash invocation")
  }
  assert_eq(invocation.arguments(), "")
  // Unknown commands still parse — dispatch is independent of registration.
  let unknown = @composer.Model("")
  unknown.insert_user_text("/unknown focus")
  guard slash_command_invocation_for_composer(specs, unknown)
    is Some(unknown_inv) else {
    fail("expected unknown command to parse syntactically")
  }
  assert_eq(unknown_inv.name(), "unknown")
  assert_eq(unknown_inv.arguments(), "focus")
  // With no commands configured the feature is off: a slash line is not an
  // invocation, so it stays ordinary input.
  let no_commands : @slash.SlashCommands = []
  let disabled = @composer.Model("")
  disabled.insert_user_text("/path/to/file")
  assert_true(
    slash_command_invocation_for_composer(no_commands, disabled) is None,
  )
}

///|
test "enter submits slash-prefixed input when no commands are configured" {
  let no_commands : @slash.SlashCommands = []
  assert_true(
    ui_enter_decision(
      no_commands,
      composer_with("/path"),
      CompletionState(),
      menu_visible=true,
    )
    is SubmitInput,
  )
}

///|
test "enter dispatches unknown slash commands to the handler" {
  // An unknown command must reach the handler (which reports the error) rather
  // than being sent to the agent as a prompt or swallowed as a notice.
  guard ui_enter_decision(
      command_specs(),
      composer_with("/doesnotexist test"),
      CompletionState(),
      menu_visible=true,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected unknown command with arguments to dispatch")
  }
  assert_eq(name, "doesnotexist")
  assert_eq(arguments, "test")
  guard ui_enter_decision(
      command_specs(),
      composer_with("/doesnotexist"),
      CompletionState(),
      menu_visible=true,
    )
    is RunSlashCommand(name=bare_name, arguments=bare_args) else {
    fail("expected bare unknown command to dispatch")
  }
  assert_eq(bare_name, "doesnotexist")
  assert_eq(bare_args, "")
}
