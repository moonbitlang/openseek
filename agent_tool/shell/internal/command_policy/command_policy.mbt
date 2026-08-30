///|
/// Apply shell command policy using an already-computed shell parse result.
///
/// This is used by `shell` so policy and follow-up Moon checks share one parse
/// of the same command string.
pub fn moonbit_command_policy_error_for_parse(
  cmd : String,
  parsed : @shell_parse.ParseResult,
) -> String? {
  if @shell_parse.contains_command(parsed, "moon_cmd") {
    Some(moon_cmd_error_message())
  } else if parsed is Simple(commands) {
    if commands.any(sed_edits_files) {
      Some(sed_in_place_error_message())
    } else {
      None
    }
  } else if first_command_word(shell_words(cmd)) == Some("moon_cmd") {
    // Too-complex parse (globs, expansions, heredocs): keep only the narrow
    // leading-word `moon_cmd` typo fallback. `sed -i` is blocked solely on the
    // precise `Simple` path above — a rough text scan of an unparseable command
    // risks blocking read-only ones (a quoted `|` in `grep 'a|sed -i' *.x`, a
    // heredoc body that writes `sed -i`), and a false block is worse than
    // missing a globbed edit. Recovering globbed `sed -i` cleanly means teaching
    // the lexer to treat an unquoted glob as an opaque word so the command stays
    // `Simple`; that shared-parser change is left for a follow-up.
    Some(moon_cmd_error_message())
  } else {
    None
  }
}

///|
fn moon_cmd_error_message() -> String {
  "error: moon_cmd is not a shell command; run moon subcommands like `moon check` or `moon test` through shell directly"
}

///|
fn sed_in_place_error_message() -> String {
  (
    #|error: `sed -i` edits files in place and is unreliable for code changes; use
    #|line-anchored `edit` (or `multi_edit` for several fixes in one file) for source
    #|changes
  )
}

///|
/// True when `command` is `sed` (after any `env`/`command`/`builtin` wrapper,
/// and ignoring a `/usr/bin/` style path) invoked with an in-place edit flag.
/// Read-only `sed` — `sed -n '1,5p' file`, `... | sed s/a/b/`, or a non-`sed`
/// `-i` such as `grep -i` / `env -i sed ...` — is left alone.
fn sed_edits_files(command : @shell_parse.SimpleCommand) -> Bool {
  guard command.command_name() is Some(name) else { return false }
  guard command_basename(name) == "sed" else { return false }
  guard command.command_index() is Some(start) else { return false }
  // `command_index` skips the wrapper, so scan only `sed`'s own arguments; the
  // argv is already unquoted by the parser.
  scan_sed_args_for_in_place(command.argv, start + 1)
}

///|
/// Scan `sed` arguments starting at `start` for an in-place flag. `-e`/`-f` (and
/// `--expression`/`--file`) consume the next word as their script/file value, so
/// that operand is skipped — `sed -f -i file` reads a script file named `-i`, it
/// is not an in-place edit. Stops at `--` (the rest are file operands).
fn scan_sed_args_for_in_place(args : Array[String], start : Int) -> Bool {
  let mut index = start
  while index < args.length() {
    let arg = args[index]
    if arg == "--" {
      break
    }
    if is_sed_in_place_flag(arg) {
      return true
    }
    index += if sed_option_consumes_next(arg) { 2 } else { 1 }
  }
  false
}

///|
/// Whether a `sed` short/long option takes the *next* word as its value (so the
/// scanner must skip that operand): a `-e`/`-f` cluster whose `e`/`f` is the last
/// character, or `--expression`/`--file` without an attached `=value`.
fn sed_option_consumes_next(arg : String) -> Bool {
  lexmatch arg {
    re"^--(expression|file)$" => true
    // A short cluster whose first `e`/`f`/`i` is an `e` or `f` in final
    // position: that flag consumes the NEXT word as its value. An `i` first,
    // or an `e`/`f` with an attached value, consumes nothing.
    re"^-([ef]|[^ief\-][^ief]*[ef])$" => true
    _ => false
  }
}

///|
/// The final path component of a command word, so a path-qualified `sed`
/// (`/usr/bin/sed`, `./sed`) compares equal to `sed`. Handles both separators.
fn command_basename(name : String) -> String {
  let normalized = name.replace_all(old="\\", new="/")
  lexmatch normalized {
    // Greedy `.*` runs to the LAST slash; the remainder is the basename.
    (re"^.*/", after=base) => base.to_owned()
    _ => name
  }
}

///|
/// Whether a single `sed` argument requests in-place editing: the long
/// `--in-place[=suffix]` form, or a short cluster containing `i` (`-i`, `-i.bak`,
/// `-Ei`). `-e`/`-f` consume the rest of the token as their value, so an `i`
/// inside a script like `-e's/i/x/'` is not mistaken for `-i`.
fn is_sed_in_place_flag(arg : String) -> Bool {
  lexmatch arg {
    re"^--in-place(=.*)?$" => true
    // A short cluster whose first `e`/`f`/`i` is an `i` (any position — the
    // rest of the token is its in-place suffix, e.g. `-i.bak`). Start-anchored
    // prefix match on purpose: the suffix after `i` is arbitrary.
    (re"^-([^ief\-][^ief]*)?i", after=_) => true
    _ => false
  }
}

///|
fn shell_words(cmd : String) -> Array[String] {
  let words : Array[String] = []
  for piece in cmd.split(" ") {
    let word = clean_shell_word(piece)
    if word != "" {
      words.push(word)
    }
  }
  words
}

///|
fn clean_shell_word(word : StringView) -> String {
  "\{word.trim(chars="\t\r\n ").trim(chars=";&|()")}"
}

///|
fn first_command_word(words : Array[String]) -> String? {
  for word in words {
    if !looks_like_env_assignment(word) {
      return Some(word)
    }
  }
  None
}

///|
fn looks_like_env_assignment(word : String) -> Bool {
  if word.contains("/") || word.contains("-") {
    return false
  }
  [..word.split("=")] is [name, value] && !name.is_empty() && !value.is_empty()
}
