///|
/// Policy gate for agent shell commands: returns the error to feed back to
/// the model when `cmd` must not run, or `None` when it may.
///
/// The blocked commands are not dangerous — they are redirections. `moon
/// check` (bare, behind `cd`, or embedded in a compound command) is pushed to
/// the `moon_check` tool so the agent gets persistent watcher feedback
/// instead of a one-shot run, and the tool name `moon_cmd` typed as a shell
/// command is pointed back at the real tools. Each error's wording tells the
/// model what to do instead, because the model is the caller who reads it.
pub fn moonbit_command_policy_error(cmd : String) -> String? {
  let words = shell_words(cmd)
  let command_index = first_command_word_index(words)
  match command_index {
    None => None
    Some(index) => {
      let first = words[index]
      if first == "moon_cmd" {
        return Some(
          "error: moon_cmd is a tool name, not a shell command; use `moon ...` through shell, and use moon_check for `moon check`",
        )
      }
      if first == "moon" && index + 1 < words.length() {
        let subcommand = words[index + 1]
        if guarded_moon_subcommands().contains(subcommand) {
          return Some(
            "error: shell blocked `moon check`; use the moon_check tool for persistent compiler feedback",
          )
        }
      }
      if contains_guarded_moon_fragment(cmd) {
        Some(
          "error: shell blocked an embedded `moon check`; use the shell tool's cwd field plus moon_check instead of `cd ... && moon check`",
        )
      } else {
        None
      }
    }
  }
}

///|
fn guarded_moon_subcommands() -> Array[String] {
  ["check"]
}

///|
fn shell_words(cmd : String) -> Array[String] {
  let words : Array[String] = []
  for piece in cmd.split(" ") {
    let word = clean_shell_word(piece.to_owned())
    if word != "" {
      words.push(word)
    }
  }
  words
}

///|
fn clean_shell_word(word : String) -> String {
  word.trim(chars="\t\r\n ").to_owned().trim(chars=";&|()").to_owned()
}

///|
fn first_command_word_index(words : Array[String]) -> Int? {
  for index, word in words {
    if !looks_like_env_assignment(word) {
      return Some(index)
    }
  }
  None
}

///|
fn looks_like_env_assignment(word : String) -> Bool {
  if word.contains("/") || word.contains("-") {
    return false
  }
  let parts = word.split("=").map(part => part.to_owned()).collect()
  parts.length() == 2 && parts[0] != "" && parts[1] != ""
}

///|
fn contains_guarded_moon_fragment(cmd : String) -> Bool {
  let probes = ["&& moon ", "; moon ", "\nmoon "]
  for probe in probes {
    for subcommand in guarded_moon_subcommands() {
      if cmd.contains(probe + subcommand) {
        return true
      }
    }
  }
  false
}
