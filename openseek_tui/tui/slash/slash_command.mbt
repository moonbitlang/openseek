///|
/// One slash command the UI can offer in the input-completion menu.
///
/// A command takes no static argument candidates: argument pickers are opened by
/// the command handler with freshly-fetched items (see `Ui::open_picker`), so the
/// spec only names the command and describes it for the name-completion menu.
#derive(Eq, Debug)
struct SlashCommandSpec {
  name : String
  description : String
  multiline_arguments : Bool
}

///|
/// Build a slash command spec. `name` does not include the leading slash.
///
/// `multiline_arguments` lets the command take text spanning several lines,
/// as in `/name` followed by Shift-Enter and a paragraph. Other commands only
/// dispatch from a single-line entry, so pasting multi-line text that happens
/// to start with their name (`/exit` and a newline) stays ordinary input.
pub fn SlashCommandSpec::SlashCommandSpec(
  name~ : String,
  description~ : String,
  multiline_arguments~ : Bool = false,
) -> SlashCommandSpec {
  { name, description, multiline_arguments, }
}

///|
/// Whether the command can take arguments spanning several lines.
pub fn SlashCommandSpec::multiline_arguments(self : SlashCommandSpec) -> Bool {
  self.multiline_arguments
}

///|
/// An ordered set of slash commands the UI can offer and dispatch.
pub(all) struct SlashCommands(Array[SlashCommandSpec])

///|
/// Whether there are no commands.
pub fn SlashCommands::is_empty(self : SlashCommands) -> Bool {
  self.0.is_empty()
}

///|
/// Completion items, one per command, for the leading-slash menu.
pub fn SlashCommands::completion_items(
  self : SlashCommands,
) -> Array[@completion.CompletionItem] {
  [
    for command in self.0 => {
      CompletionItem(
        label="/\{command.name()}",
        insert_text=command.name(),
        description=command.description(),
      )
    }
  ]
}

///|
/// A slash command reference parsed from input text: the command name (without
/// the leading slash) and its trimmed argument string. Parsing is syntactic
/// only; resolve the name against a `SlashCommands` set to know if it is known.
#derive(Eq, Debug)
struct SlashCommandInvocation {
  name : String
  arguments : String
}

///|
/// Parse `text` as a single `/name arguments` entry. Returns None unless `text`
/// is `/`-prefixed with a non-empty name; the name is not checked against any
/// command set.
pub fn SlashCommandInvocation::parse(text : String) -> SlashCommandInvocation? {
  guard text.strip_prefix("/") is Some(rest) else { return None }
  // The name runs up to the first whitespace; the remainder, trimmed, is the
  // argument string.
  let name = StringBuilder()
  for ch in rest {
    if ch.is_whitespace() {
      break
    }
    name.write_char(ch)
  }
  let name = name.to_string()
  // The name must be non-empty and not itself start with `/`: a doubled leading
  // slash (`//`, `//e`) is not a command invocation, and treating it as the name
  // `/`/`/e` would let it match a command by its `/`-prefixed display label.
  guard !name.is_empty() && !name.has_prefix("/") else { return None }
  let arguments = rest.exact_view(start=name.length()).trim().to_owned()
  Some({ name, arguments, })
}

///|
/// Command name without the leading slash.
pub fn SlashCommandInvocation::name(self : SlashCommandInvocation) -> String {
  self.name
}

///|
/// Trimmed argument string following the command name.
pub fn SlashCommandInvocation::arguments(
  self : SlashCommandInvocation,
) -> String {
  self.arguments
}

///|
/// Whether the text following a leading slash already contains an argument
/// separator (whitespace), i.e. the user has moved past the command name.
pub fn has_arguments(rest : String) -> Bool {
  rest.any(c => c.is_whitespace())
}

///|
pub extend SlashCommandInvocation with Debug::{to_repr}

///|
pub extend SlashCommandInvocation with Eq::{equal, not_equal}

///|
pub extend SlashCommandSpec with Debug::{to_repr}

///|
pub extend SlashCommandSpec with Eq::{equal, not_equal}
