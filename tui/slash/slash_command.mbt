///|
/// One slash command the UI can offer in the input-completion menu.
///
/// A command takes no static argument candidates: argument pickers are opened by
/// the command handler with freshly-fetched items (see `Ui::open_picker`), so the
/// spec only names the command and describes it for the name-completion menu.
struct SlashCommandSpec {
  name : String
  description : String
} derive(Eq, Debug)

///|
/// Build a slash command spec. `name` does not include the leading slash.
pub fn SlashCommandSpec::new(
  name~ : String,
  description~ : String,
) -> SlashCommandSpec {
  { name, description }
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
      @completion.CompletionItem::new(
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
struct SlashCommandInvocation {
  name : String
  arguments : String
} derive(Eq, Debug)

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
  let arguments = rest.view(start_offset=name.length()).trim().to_owned()
  Some({ name, arguments })
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
#deprecated
pub extend SlashCommandInvocation with Debug::{to_repr}

///|
pub extend SlashCommandInvocation with Eq::{equal, not_equal}

///|
#deprecated
pub extend SlashCommandSpec with Debug::{to_repr}

///|
pub extend SlashCommandSpec with Eq::{equal, not_equal}
