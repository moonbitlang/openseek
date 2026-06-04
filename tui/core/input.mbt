// The semantic input the user submits, plus its projection into a `@doc.Doc`.

///|
/// A submitted input: a prompt for the agent, or a shell command (entered with a
/// leading `!`).
pub(all) enum Input {
  Prompt(String)
  Command(String)
} derive(Eq, Debug)

///|
/// The `❯ ` prompt marker shown before normal agent-steering input, shared so
/// the composer and renderers measure and draw the same cached display run.
pub let prompt_prefix : @displaytext.DisplayText = DisplayText("❯ ")

///|
let command_prefix : @displaytext.DisplayText = DisplayText("$ ")

///|
/// The prefix marker shown before this input (`❯ ` for prompts, `$ ` for shell
/// commands).
pub fn Input::prefix(self : Input) -> @displaytext.DisplayText {
  match self {
    Prompt(_) => prompt_prefix
    Command(_) => command_prefix
  }
}

///|
/// The raw text of this input, without its prefix.
pub fn Input::text(self : Input) -> String {
  match self {
    Prompt(text) => text
    Command(command) => command
  }
}

///|
/// Project the input into a renderable `@doc.Doc`: the first line carries the
/// input's `prefix` and continuation lines are indented two columns, all in the
/// prompt style.
impl @doc.ToDoc for Input with fn to_doc(self) {
  let source = @displaytext.split_lines(self.text())
  let texts : Array[@doc.Text] = []
  for index in 0..<source.length() {
    let line = source[index]
    texts.push(
      Text([
        Span(
          if index == 0 {
            self.prefix()
          } else {
            DisplayText("  ")
          },
          style=@doc.Style::prompt(),
        ),
        @doc.Span::plain(line.text()),
      ]),
    )
  }
  Doc(texts)
}
