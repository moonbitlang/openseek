///|
/// Tool definition for `edit`: replaces exact text in `arguments.path`.
///
/// ## Arguments
/// - `path` (string, required): filesystem path to edit.
/// - `old_string` (string, required): exact text to replace. Empty selects
///   insertion mode: `new_string` is inserted at the start of `start_line`,
///   and a `start_line` past the last line appends at end of file.
/// - `new_string` (string, required): replacement text. It must differ from
///   `old_string`.
/// - `start_line` (integer, required): 1-based inclusive first line to search.
/// - `end_line` (integer, optional): 1-based inclusive last line to search.
/// - `replace_all=true` is rejected. Use `multi_edit` for multiple explicit
///   line-anchored replacements.
/// - `replace_all_preview` (boolean, optional, default false): preview mode —
///   the file is NOT modified. Every match of `old_string` in the line range
///   is reported with surrounding context, plus a ready-to-review `multi_edit`
///   edits array; the agent keeps the entries to apply and drops the rest.
///   The pipeline is complementary, not overlapping: the preview filters what
///   the compiler cannot see (comments, docs, `.mbt.md` prose, string
///   literals), and `multi_edit` verifies the applied subset with its parse
///   gate and moon check auto-revert. For typed-code renames the compiler
///   loop (deprecated alias + fix what `moon check` flags) remains the better
///   tool — seeing a code-heavy match list is the cue to switch to it.
/// - `revert_on_parse_errors` (boolean, optional, default true): before an
///   edit to a syncheck input (`.mbt`, `.mbt.md`, `moon.mod`, `moon.pkg`) is
///   written, the edited result is parsed standalone (`moonc syncheck`); an
///   edit that would introduce new lex/parse errors is rejected and the file is
///   left untouched. Pre-existing parse errors never trigger the gate; in
///   `.mbt.md` only the checked fenced blocks are parsed.
///
/// ## Result
/// - `Respond(ToolOutput("ok: replaced <n> occurrence(s) at line <line> in <path>"))`
///   on success. Insertions report the actual inclusive line range the new
///   content occupies — `ok: inserted line(s) <range> in <path>`, or
///   `ok: appended line(s) <range> at end of file in <path>` when the
///   (possibly clamped) insertion point is end of file.
/// - `Respond(ToolOutput("rejected: the edit would introduce ...", is_error=true))`
///   when the parse gate refused an edit whose result does not parse.
/// - `Respond(ToolOutput("error editing <path>: ...", is_error=true))` for
///   filesystem failures, empty/no-op edits, or missing matches.
/// - `Respond(ToolOutput("error: edit requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
  file_state? : @agent_tool.FileStateMap = FileStateMap(),
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="edit",
    description=(
      #|Replace the first exact text span at or after arguments.start_line in
      #|arguments.path with arguments.new_string. Optional end_line restricts the search
      #|to a 1-based inclusive line range. Because start_line anchors the location,
      #|old_string can be a small exact span instead of a large context block. To INSERT
      #|new code instead of replacing, set old_string to the empty string: new_string is
      #|inserted at the start of start_line. To APPEND at end of file, pass any start_line
      #|past the last line (e.g. 999999) — no need to know the file's length; the result
      #|reports the actual inclusive line range the new content landed on. In MoonBit
      #|top-level order does not matter, so add new functions, tests, or types by
      #|appending at end of file — an append cannot mismatch an anchor; reserve mid-file
      #|insertion for grouping related code. An edit that would introduce lex/parse errors
      #|into a syntax-checkable file (.mbt, .mbt.md, moon.mod, moon.pkg) is rejected
      #|BEFORE writing and the parse errors are returned — see revert_on_parse_errors. For
      #|multiple compiler-feedback fixes in one file, use multi_edit with explicit
      #|line-anchored edits. To change EVERY occurrence of a string, pass
      #|replace_all_preview=true: the file is not modified; instead every match site is
      #|listed with context plus a ready-to-review multi_edit edits array — keep the
      #|entries to apply, drop the rest. That preview-select-apply path is for text the
      #|compiler cannot see (comments, docs, .mbt.md prose, string literals); for
      #|typed-code renames prefer the compiler loop (add the new name, deprecate the old,
      #|fix what moon check flags).
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "old_string": { "type": "string" },
        "new_string": { "type": "string" },
        "start_line": { "type": "integer" },
        "end_line": { "type": "integer" },
        "revert_on_parse_errors": {
          "type": "boolean",
          "description": (
            #|Syntax gate, on by default. Before the edit is written to a syntax-checkable
            #|file (.mbt, .mbt.md, moon.mod, moon.pkg), the edited result is parsed
            #|standalone (moonc syncheck); an edit that would INTRODUCE new lex/parse
            #|errors — measured against the pre-edit content parsed the same way, so
            #|pre-existing parse errors are ignored — is REJECTED, the file is left
            #|untouched, and the call returns the errors with excerpts of the would-be
            #|content. Type errors never trigger the gate (they may be a legitimate
            #|transient state); in .mbt.md only the checked (`mbt check` / `moonbit
            #|check`) fenced blocks are parsed. Set false only to intentionally produce
            #|content that does not parse (e.g. a fixture).
          ),
          "examples": [false],
        },
        "replace_all_preview": {
          "type": "boolean",
          "description": (
            #|Preview mode: the file is NOT modified. Every match of old_string in the
            #|start_line/end_line range is listed with surrounding context lines, plus a
            #|ready-to-use multi_edit `edits` array — REVIEW the sites, keep the entries
            #|to apply, drop the rest, and pass them to multi_edit (which then verifies
            #|the batch with moon check). Use this where the compiler cannot see —
            #|comments, doc prose, .mbt.md text, string literals; for typed-code renames
            #|prefer the compiler loop (add the new name, deprecate the old, fix what moon
            #|check flags), and if the match list turns out to be code-heavy or
            #|type-ambiguous, switch to that loop instead of applying.
          ),
          "examples": [true],
        },
      },
      "required": ["path", "old_string", "new_string", "start_line"],
    }),
    execute=Async(arguments => {
      execute_with_workspace(
        workspace_root,
        file_state,
        arguments,
        write_scope?,
      )
    }),
  )
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.respond(
        "error: edit requires \{message}",
        is_error=true,
      )
    }
  }
  let path = @workspace_path.resolve(workspace_root, input.path)
  // Containment gate for confined (worker) registries. Previews write
  // nothing, so they stay readable everywhere; the write itself is gated
  // again in commit_edit, immediately before the file is touched.
  if !input.replace_all_preview &&
    write_scope is Some(scope) &&
    scope.deny_reason(path) is Some(reason) {
    return @agent_tool.respond(
      "error editing \{path}: write blocked: \{reason}",
      is_error=true,
      brief="edit \{@agent_tool.brief_basename(path)}",
    )
  }
  edit_file(input, path~, file_state~, write_scope?)
}

///|
async fn edit_file(
  input : @decode.EditInput,
  path~ : String,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  // Every failure names the file it tried to edit so the viz can show
  // `→ edit · edit <file> 🚩` on the folded call line.
  let fail_brief = "edit \{@agent_tool.brief_basename(path)}"
  fn err(message : String) -> @agent_tool.ToolAction {
    @agent_tool.respond(
      "error editing \{path}: \{message}",
      is_error=true,
      brief=fail_brief,
    )
  }

  if input.replace_all {
    return err(
      "replace_all=true is no longer supported; use replace_all_preview=true to review every match as a multi_edit edits array, or multi_edit with explicit line-anchored edits",
    )
  }
  if input.old_string == "" && input.new_string == "" {
    return err("old_string and new_string are both empty")
  }
  if input.old_string == input.new_string {
    let content = @fs.read_file(path).text()
    return err(
      "old_string and new_string are identical\{old_string_context(content, input.old_string, input.start_line, input.end_line)}\n(old_string matches new_string exactly — the file at that location may already contain this text; re-read the file and adjust the edit)",
    )
  }
  if input.replace_all_preview {
    guard input.old_string != "" else {
      return err(
        "replace_all_preview requires a non-empty old_string (an insertion has no match sites to preview)",
      )
    }
    return preview_replace_all(input, path~, err)
  }
  let content = @fs.read_file(path).text()
  if input.old_string == "" {
    // Insertion: insert new_string at the start of start_line (a zero-width
    // edit). Any start_line past the last line clamps to end of file, so a
    // deliberately large value appends without knowing the file's length; the
    // summary reports the actual inclusive line range the new content
    // occupies — real coordinates the model can anchor follow-up edits on,
    // not the (possibly clamped) requested line.
    let at = @line_offset.line_start_offset(content, input.start_line).clamp(
      min=0,
      max=content.length(),
    )
    let first_line = line_number_at_offset(content, at)
    let last_line = first_line + inserted_line_span(input.new_string) - 1
    let (span, brief_span) = if last_line > first_line {
      ("lines \{first_line}-\{last_line}", "\{first_line}-\{last_line}")
    } else {
      ("line \{first_line}", "\{first_line}")
    }
    let (summary, ok_brief) = if at == content.length() {
      (
        "ok: appended \{span} at end of file in \{path}",
        "edited \{@agent_tool.brief_basename(path)}:\{brief_span} (append)",
      )
    } else {
      (
        "ok: inserted \{span} in \{path}",
        "edited \{@agent_tool.brief_basename(path)}:\{brief_span} (insert)",
      )
    }
    let new_content = "\{content.unsafe_substring(start=0, end=at)}\{input.new_string}\{content.unsafe_substring(start=at, end=content.length())}"
    return commit_edit(
      path,
      original_content=content,
      new_content~,
      revert_on_parse_errors=input.revert_on_parse_errors,
      fail_brief~,
      summary~,
      ok_brief~,
      file_state~,
      write_scope?,
    )
  }
  let (norm_content, offset_map) = @matching.normalize_content_for_matching(
    content,
  )
  let region = select_edit_region(norm_content, input)
  let (match_start, is_quote_match) = match region.body.find(input.old_string) {
    Some(start) => (start, false)
    None =>
      match
        @matching.find_quote_normalized_match(region.body, input.old_string) {
        Some(start) => (start, true)
        None => {
          let file_hints = StringBuilder()
          if @matching.has_crlf(content) {
            file_hints.write_string(
              "— the file uses CRLF line endings; old_string uses LF — re-read the file and copy the exact text",
            )
          }
          if @matching.has_curly_quotes(content) {
            if file_hints.to_string().length() > 0 {
              file_hints.write_char('\n')
            }
            file_hints.write_string(
              "— the file contains curly/smart quotes; models can only output straight quotes — re-read the file and copy the exact text from the file",
            )
          }
          return err(
            "old_string not found" +
            range_detail(input) +
            old_string_context(
              content,
              input.old_string,
              input.start_line,
              input.end_line,
              file_hints=file_hints.to_string(),
            ),
          )
        }
      }
  }
  let norm_global = region.prefix.length() + match_start
  let orig_global = offset_map[norm_global]
  let orig_end = if norm_global + input.old_string.length() <
    offset_map.length() {
    offset_map[norm_global + input.old_string.length()]
  } else {
    content.length()
  }
  let match_line = line_number_at_offset(content, orig_global)
  let new_content = "\{content.unsafe_substring(start=0, end=orig_global)}\{input.new_string}\{content.unsafe_substring(start=orig_end, end=content.length())}"
  let summary = if is_quote_match {
    "ok: replaced 1 occurrence(s) at line \{match_line} in \{path} (quote-normalized match)"
  } else {
    "ok: replaced 1 occurrence(s) at line \{match_line} in \{path}"
  }
  commit_edit(
    path,
    original_content=content,
    new_content~,
    revert_on_parse_errors=input.revert_on_parse_errors,
    fail_brief~,
    summary~,
    ok_brief="edited \{@agent_tool.brief_basename(path)}:\{match_line} (1×)",
    file_state~,
    write_scope?,
  )
}

///|
/// At most this many match sites are rendered (and emitted as edits) in one
/// preview; matches beyond the cap are reported as a count with a nudge to
/// narrow the line range, so a pathological pattern cannot flood the turn.
const PreviewSiteCap : Int = 40

///|
/// Context lines shown above and below each match site.
const PreviewContextLines : Int = 2

///|
/// Longest rendered context line; longer lines are cut with an ellipsis. The
/// emitted edits always carry the exact strings — only the display truncates.
const PreviewLineDisplayCap : Int = 200

///|
/// Longest line a many-match site may embed as a whole-line entry, and the
/// same bound applied to the ESTIMATED expanded replacement (line length plus
/// per-match growth, computed arithmetically BEFORE `replace_all` so a long
/// `new_string` times thousands of matches can never materialize hundreds of
/// MB). Sites past either bound are reported with a note instead of an entry.
const PreviewEntryCharsCap : Int = 4_096

///|
/// Budget for the rendered context blocks, and separately for the entries
/// array text. The production turn loop clamps tool results at 60k units and
/// cuts the TAIL — an unbudgeted report would lose the end of the JSON array
/// and corrupt every entry. Context blocks and entries are each capped so the
/// whole report stays safely under the clamp; omissions are counted and
/// stated, and the array always closes validly.
const PreviewContextBudgetChars : Int = 24_000

///|
const PreviewEntriesBudgetChars : Int = 24_000

///|
/// `replace_all_preview=true`: report every match of `old_string` in the
/// selected line range — surrounding context for review plus a ready-to-use
/// `multi_edit` edits array — WITHOUT modifying the file. The selection step
/// is the point: the compiler cannot vet prose/comment/string sites, so the
/// agent filters those, and `multi_edit`'s own gates (parse gate, moon check
/// auto-revert) verify the applied batch afterwards. Several matches on one
/// line collapse into a single whole-line entry, because two line-anchored
/// edits with the same anchor would both hit the first occurrence.
async fn preview_replace_all(
  input : @decode.EditInput,
  path~ : String,
  err : (String) -> @agent_tool.ToolAction,
) -> @agent_tool.ToolAction {
  let orig_content = @fs.read_file(path).text()
  let (content, _) = @matching.normalize_content_for_matching(orig_content)
  let region = select_edit_region(content, input)
  // The cap bounds emitted SITES, not raw matches: matches arrive in order, so
  // same-line matches always merge into the LAST site, and only a match that
  // would open a new site past the cap stops the scan. Capping raw matches
  // instead would let one many-match line starve every later site (and
  // under-count the merges of the line it did emit). The scan is LINEAR in
  // the body however dense the matches: views (no tail copies), line numbers
  // counted incrementally, and a many-match line's whole-line entry built
  // once at site finalization — a one-char needle over minified text must not
  // stall the tool.
  let single_line = !input.old_string.contains("\n")
  let sites : Array[PreviewSite] = []
  let notes : Array[String] = []
  let mut total_matches = 0
  let mut more = false
  // Incremental line tracking; match offsets only move forward.
  let mut scan_offset = 0
  let mut scan_line = 1
  fn line_at(offset : Int) -> Int {
    while scan_offset < offset {
      if content[scan_offset] == '\n' {
        scan_line += 1
      }
      scan_offset += 1
    }
    scan_line
  }

  // One O(file) pass; per-line lookups during finalization and context
  // rendering are then O(1) instead of rescanning from the file start (40
  // sites × 5 context lines was ~400 full-file scans on a large file).
  let line_starts = line_start_index(content)
  // Same-line merges only bump this counter; the site's whole-line entry (or
  // its too-large note) is built ONCE when the site is finalized.
  let mut last_site_extra_matches = 0
  fn finalize_last_site() -> Unit {
    guard last_site_extra_matches > 0 else { return }
    let site = sites[sites.length() - 1]
    let match_count = 1 + last_site_extra_matches
    last_site_extra_matches = 0
    let line = line_text_at(content, line_starts, site.first_line)
    // Estimate the expanded replacement ARITHMETICALLY before building it: a
    // long new_string times thousands of matches must never be materialized
    // just to be found oversized (4k one-char matches × a 50k replacement is
    // ~200M units). Embedding a huge line (or expansion) twice in the edits
    // array would also blow the response past the outer clamp. Int64: the
    // estimate itself must not overflow — 4096 matches × 2^19 growth wraps a
    // 32-bit Int negative and would sail PAST the guard it exists for.
    let growth = (input.new_string.length() - input.old_string.length()).to_int64()
    let expanded = line.length().to_int64() +
      match_count.to_int64() * (if growth > 0 { growth } else { 0 })
    if line.length() > PreviewEntryCharsCap ||
      expanded > PreviewEntryCharsCap.to_int64() {
      notes.push(
        "line \{site.first_line}: \{match_count} matches, but the whole-line entry would be too large to emit (line \{line.length()} chars, combined replacement ≈ \{expanded}) — narrow old_string (with more surrounding context) or edit that line manually",
      )
      sites[sites.length() - 1] = { ..site, match_count, emit: false, }
      return
    }
    sites[sites.length() - 1] = {
      ..site,
      match_count,
      old_string: line,
      new_string: line.replace_all(old=input.old_string, new=input.new_string),
    }
  }

  let prefix_length = region.prefix.length()
  let needle = input.old_string[:]
  let mut from = 0
  for ;; {
    guard region.body[from:].find(needle) is Some(found) else { break }
    let offset = from + found
    from = offset + input.old_string.length()
    let global = prefix_length + offset
    let first_line = line_at(global)
    let last_line = line_at(global + input.old_string.length() - 1)
    if sites is [.., last_site] && last_site.first_line == first_line {
      if single_line {
        // A second match on the same line: two line-anchored edits with the
        // same anchor would both hit the first occurrence, so the site becomes
        // one whole-line entry with every match on the line applied.
        total_matches += 1
        last_site_extra_matches += 1
      } else {
        notes.push(
          "line \{first_line}: an additional multiline match starts on this line — not expressible as a separate line-anchored edit; re-run the preview after applying the first",
        )
      }
      continue
    }
    if sites.length() == PreviewSiteCap {
      more = true
      break
    }
    finalize_last_site()
    total_matches += 1
    sites.push({
      first_line,
      last_line,
      match_count: 1,
      old_string: input.old_string,
      new_string: input.new_string,
      emit: true,
    })
  }
  finalize_last_site()
  guard sites.length() > 0 else {
    return err("old_string not found\{range_detail(input)}")
  }
  let total_lines = total_line_count(content)
  let report = StringBuilder()
  if more {
    report.write_string(
      "preview: showing the first \{sites.length()} match site(s) for old_string in \{path} (file NOT modified) — more sites exist; narrow with start_line/end_line to see the rest\n",
    )
  } else {
    report.write_string(
      "preview: \{total_matches} match(es) at \{sites.length()} site(s) for old_string in \{path} (file NOT modified)\n",
    )
  }
  let mut context_chars = 0
  let mut context_omitted = 0
  for site in sites {
    let block = StringBuilder()
    block.write_string("\n\{preview_site_header(site)}\n")
    render_site_context(block, content, line_starts, site, total_lines)
    let text = block.to_string()
    if context_chars + text.length() > PreviewContextBudgetChars {
      context_omitted += 1
      continue
    }
    context_chars += text.length()
    report.write_string(text)
  }
  if context_omitted > 0 {
    report.write_string(
      "\n(context for \{context_omitted} site(s) omitted to keep this response within the result cap — their entries below still cover them)\n",
    )
  }
  for note in notes {
    report.write_string("\nnote: \{note}\n")
  }
  let entry_texts : Array[String] = []
  let mut entries_chars = 0
  let mut entries_omitted = 0
  for site in sites {
    guard site.emit else { continue }
    let entry : Json = {
      "file": input.path.to_json(),
      "old_string": site.old_string.to_json(),
      "new_string": site.new_string.to_json(),
      "start_line": site.first_line.to_json(),
    }
    let text = entry.stringify()
    if entries_chars + text.length() > PreviewEntriesBudgetChars {
      entries_omitted += 1
      continue
    }
    entries_chars += text.length()
    entry_texts.push(text)
  }
  report.write_string(
    "\nmulti_edit edits array — line numbers refer to the file AS IT IS NOW; review, keep the entries to apply, drop the rest:\n[\n",
  )
  for index, text in entry_texts {
    let separator = if index + 1 < entry_texts.length() { "," } else { "" }
    report.write_string("  \{text}\{separator}\n")
  }
  report.write_string("]\n")
  if entries_omitted > 0 {
    report.write_string(
      "(\{entries_omitted} entr(y/ies) omitted to keep the array parseable under the result cap — narrow with start_line/end_line and preview again for the rest)\n",
    )
  }
  report.write_string(
    "\nreview guidance: text matches cannot see types — for typed-code renames prefer the compiler loop (add the new name, deprecate the old, fix what moon check flags), and if this list is code-heavy or type-ambiguous, switch to it instead of applying. Preview-select-apply is for what the compiler cannot check (comments, docs, .mbt.md prose, string literals); multi_edit re-verifies the applied batch (parse gate + moon check auto-revert).\n",
  )
  @agent_tool.respond(
    report.to_string(),
    brief="edit preview \{@agent_tool.brief_basename(path)} (\{sites.length()} site(s))",
  )
}

///|
priv struct PreviewSite {
  first_line : Int
  last_line : Int
  match_count : Int
  old_string : String
  new_string : String
  // False for a site shown in the report but excluded from the edits array
  // (a many-match line too long to emit as a whole-line entry).
  emit : Bool
}

///|
fn preview_site_header(site : PreviewSite) -> String {
  if site.match_count > 1 && !site.emit {
    "line \{site.first_line} (\{site.match_count} matches — no entry emitted; see the note below):"
  } else if site.match_count > 1 {
    "line \{site.first_line} (\{site.match_count} matches — the entry below replaces the WHOLE line with all of them applied; edit its new_string to change fewer):"
  } else if site.last_line > site.first_line {
    "lines \{site.first_line}-\{site.last_line}:"
  } else {
    "line \{site.first_line}:"
  }
}

///|
fn render_site_context(
  report : StringBuilder,
  content : String,
  line_starts : Array[Int],
  site : PreviewSite,
  total_lines : Int,
) -> Unit {
  let from = (site.first_line - PreviewContextLines).clamp(
    min=1,
    max=site.first_line,
  )
  let to = (site.last_line + PreviewContextLines).clamp(
    min=site.last_line,
    max=total_lines,
  )
  let width = "\{to}".length()
  for line in from..<=to {
    let marker = if line >= site.first_line && line <= site.last_line {
      ">"
    } else {
      " "
    }
    report.write_string(
      "\{marker} \{preview_pad(line, width)} | \{preview_display_line(line_text_at(content, line_starts, line))}\n",
    )
  }
}

///|
fn preview_pad(value : Int, width : Int) -> String {
  "\{value}".pad_start(width, ' ')
}

///|
fn preview_display_line(text : String) -> String {
  if text.length() <= PreviewLineDisplayCap {
    return text
  }
  "\{text.clamped_view(end=PreviewLineDisplayCap)}…"
}

///|
/// Start offset of every 1-based line, in one pass. A file ending in `\n`
/// yields a phantom trailing start equal to the length; `line_text_at`
/// resolves it to the empty string, and render ranges are clamped to
/// `total_line_count` anyway.
fn line_start_index(content : String) -> Array[Int] {
  let starts = [0]
  for index in 0..<content.length() {
    if content[index] == '\n' {
      starts.push(index + 1)
    }
  }
  starts
}

///|
fn line_text_at(
  content : String,
  line_starts : Array[Int],
  line : Int,
) -> String {
  guard line >= 1 && line <= line_starts.length() else { return "" }
  let start = line_starts[line - 1]
  let end = if line < line_starts.length() {
    line_starts[line]
  } else {
    content.length()
  }
  let text = content.unsafe_substring(start~, end~)
  if text.has_suffix("\n") {
    text.unsafe_substring(start=0, end=text.length() - 1)
  } else {
    text
  }
}

///|
fn total_line_count(content : String) -> Int {
  if content == "" {
    return 0
  }
  let count = for ch in content; count = 0 {
    continue if ch == '\n' { count + 1 } else { count }
  } nobreak {
    count
  }
  if content.has_suffix("\n") {
    count
  } else {
    count + 1
  }
}

///|
/// Shared tail for both the insertion and replacement paths: run the manifest
/// and parse-gate guards against the candidate content, then write it and
/// report success — or return the matching error `ToolAction`. `summary` and
/// `ok_brief` describe the specific edit that was made; `fail_brief` folds
/// every failure onto the same `→ edit · edit <file> 🚩` viz line.
async fn commit_edit(
  path : String,
  original_content~ : String,
  new_content~ : String,
  revert_on_parse_errors~ : Bool,
  fail_brief~ : String,
  summary~ : String,
  ok_brief~ : String,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  if @manifest_error.write_error(path, new_content) is Some(message) {
    return @agent_tool.respond(
      "error editing \{path}: \{message}",
      is_error=true,
      brief=fail_brief,
    )
  }
  if parse_gate_rejection(
      path,
      original_content~,
      new_content~,
      revert_on_parse_errors~,
    )
    is Some(rejection) {
    return rejection
  }
  // Containment re-check at the moment of writing: the early gate decided on
  // filesystem state that awaits ago may have changed (a path component
  // re-linked underneath the tool).
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
    return @agent_tool.respond(
      "error editing \{path}: write blocked: \{reason}",
      is_error=true,
      brief=fail_brief,
    )
  }
  @fs.write_file(path, new_content, create_mode=CreateOrTruncate)
  // A targeted edit preserves most of the file, so provenance depends on
  // whether the content it read (original_content) is still what the agent last
  // wrote: record_edited keeps a stronger `Created` only then, and otherwise
  // downgrades (the file was rebound to different content before this edit).
  file_state.record_edited(
    path,
    @agent_tool.content_digest(original_content),
    @agent_tool.content_digest(new_content),
  )
  let response = @auto_check.append_summary(path, summary)
  @agent_tool.respond(response, brief=ok_brief)
}

///|
/// From this many newly introduced parse errors up, the reject report stops
/// suggesting a corrected re-issue and pushes splitting the change into
/// smaller edits instead: parse errors cascade, so several of them usually
/// mean a large replacement (or a misplaced insertion) broke the file's
/// structure wholesale.
const SmallerEditsHintThreshold : Int = 3

///|
/// Pre-write syntax gate for syncheck-input edits: parse the candidate result
/// in a scratch file (moonc syncheck, no project context) and reject
/// the edit — leaving the file untouched — when it would introduce new parse
/// errors. "Introduced" compares parse-error counts against the ORIGINAL
/// content parsed the same way, so a file that already fails to parse can
/// still be edited (including partial fixes). Counts, not diagnostic
/// identities, on purpose: an edit shifts the line numbers of every
/// pre-existing error below it, so identity matching keyed on locations would
/// false-fire constantly; the blind spot (an edit that fixes one parse error
/// while introducing another, keeping the count flat) is accepted. The gate
/// applies to every syncheck input — `.mbt`, `.mbt.md` (checked fenced blocks
/// only), `moon.mod`, `moon.pkg` — under each kind the file could be classified
/// as (a cross-kind symlink is checked under both). Fail-open: when the gate
/// cannot run, the edit proceeds as before the gate existed.
async fn parse_gate_rejection(
  path : String,
  original_content~ : String,
  new_content~ : String,
  revert_on_parse_errors~ : Bool,
) -> @agent_tool.ToolAction? {
  if !revert_on_parse_errors {
    return None
  }
  // Resolve symlinks before deciding whether the gate applies: an edit through
  // a link named `alias.txt` pointing at `lib/a.mbt` must be gated like the
  // `.mbt` file it really writes (the same class `write`'s overwrite guard
  // handles with realpath).
  let target = @fs.realpath(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => path
  }
  // Gate under every syncheck kind this file could be classified as. A regular
  // file yields one kind; a symlink that crosses kinds (e.g. `link.mbt ->
  // doc.mbt.md`) yields two, and moon's classification of such a link is
  // ambiguous, so reject on the FIRST kind under which the edit introduces new
  // parse errors — that covers both interpretations. See `gate_paths`.
  for gate_path in @auto_check.gate_paths(path, target) {
    let gate = @auto_check.content_parse_errors(gate_path, new_content) catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    guard gate is Some(gate) && gate.errors.length() > 0 else { continue }
    // The edited result has parse errors under this kind; reject only when the
    // edit makes the file WORSE than its original content parsed the same way.
    let before = @auto_check.content_parse_errors(gate_path, original_content) catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    // The comparison is only sound against a COMPLETE baseline: a missing one
    // (transient tmpdir/moonc failure) gives no honest "introduced" answer, and
    // a truncated one is a lower bound whose subtraction could over-count the
    // introduced errors and false-reject. Fail open in both cases — the gate
    // must never reject on a comparison it could not actually make. A truncated
    // NEW capture is fine: its count is a lower bound, so exceeding the complete
    // baseline still proves the edit made things worse.
    guard before is Some(before) && !before.truncated else { continue }
    let before_count = before.errors.length()
    let introduced = gate.errors.length() - before_count
    if introduced <= 0 {
      continue
    }
    let bound = if gate.truncated { "≥" } else { "" }
    return Some(
      @agent_tool.respond(
        edit_reject_report(path, new_content, gate, introduced~, before_count~),
        is_error=true,
        brief="edit rejected (\{bound}\{introduced} parse error(s))",
      ),
    )
  }
  None
}

///|
/// The rejected-edit report: the file was not modified, the first parse
/// errors with excerpts synthesized from the would-be content, and how to
/// retry — a corrected re-issue for a small slip, smaller pieces when the
/// errors suggest the replacement broke the file's structure.
fn edit_reject_report(
  path : String,
  new_content : String,
  gate : @auto_check.ParseGate,
  introduced~ : Int,
  before_count~ : Int,
) -> String {
  // A truncated capture makes the introduced count a lower bound; never state
  // an exact number the gate does not know.
  let introduced_label = if gate.truncated {
    "at least \{introduced}"
  } else {
    "\{introduced}"
  }
  let head = "rejected: the edit would introduce \{introduced_label} new parse error(s) in \{path}, so the file was NOT modified."
  let pre_existing = if before_count > 0 {
    " (the file already has \{before_count} parse error(s); only counts are compared, so the excerpts below may include pre-existing errors, not only the newly introduced ones)"
  } else {
    ""
  }
  let formatted = @auto_check.format_parse_gate_errors(
    path,
    new_content,
    gate.errors,
  )
  let listed = if formatted.is_empty() {
    ""
  } else {
    "\nfirst \{formatted.length()} parse error(s), excerpted from the WOULD-BE content (not what is on disk):\n\{formatted.join("\n")}"
  }
  let retry = if introduced >= SmallerEditsHintThreshold {
    "\n\{introduced_label} new parse errors usually means the replacement would break the file's structure (an unbalanced brace, a misplaced insertion, or non-MoonBit text). Do not re-issue the same edit: split it into smaller pieces — multi_edit applies several small line-anchored edits in one validated call — and check after each step."
  } else {
    "\nre-issue the edit with a corrected new_string (check delimiters against the excerpt above)."
  }
  let opt_out = "\n(To intentionally produce content that does not parse, e.g. a fixture, pass revert_on_parse_errors=false.)"
  "\{head}\{pre_existing}\{listed}\{retry}\{opt_out}"
}

///|
#warnings("-unused_field")
priv struct EditRegion {
  prefix : String
  body : String
  suffix : String
}

///|
fn select_edit_region(
  content : String,
  input : @decode.EditInput,
) -> EditRegion {
  let start_line = input.start_line
  let start = @line_offset.line_start_offset(content, start_line)
  let end = match input.end_line {
    Some(line) => @line_offset.line_end_offset(content, line)
    None => content.length()
  }
  // `decode` guarantees end_line >= start_line when both are present. These
  // clamps make ranges beyond EOF select an empty suffix without panicking.
  let start = start.clamp(min=0, max=content.length())
  let end = end.clamp(min=start, max=content.length())
  {
    prefix: content.unsafe_substring(start=0, end=start),
    body: content.unsafe_substring(start~, end~),
    suffix: content.unsafe_substring(start=end, end=content.length()),
  }
}

///|
/// How many lines `new_string` occupies once inserted: one per newline, plus
/// one for a trailing fragment that does not end in a newline (that fragment
/// shares its line with whatever follows the insertion point). `new_string`
/// is non-empty on the insertion path — both-empty edits are rejected first.
fn inserted_line_span(new_string : String) -> Int {
  let newlines = for ch in new_string; newlines = 0 {
    continue if ch == '\n' { newlines + 1 } else { newlines }
  } nobreak {
    newlines
  }
  if new_string.has_suffix("\n") {
    newlines
  } else {
    newlines + 1
  }
}

///|
fn line_number_at_offset(content : String, offset : Int) -> Int {
  let bounded_offset = offset.clamp(min=0, max=content.length())
  for cursor in 0..<bounded_offset; line = 1 {
    if content[cursor] == '\n' {
      continue line + 1
    }
    continue line
  } nobreak {
    line
  }
}

///|

///|
fn range_detail(input : @decode.EditInput) -> String {
  match input.end_line {
    Some(end) => " in line range \{input.start_line}-\{end}"
    None => " from line \{input.start_line}"
  }
}

///|
/// Build a structured diagnostic when `old_string` is not found: file-level
/// hints first, then the file context in a code block, then the first
/// character difference with a specific mismatch hint.
fn old_string_context(
  content : String,
  old_string : String,
  start_line : Int,
  end_line : Int?,
  file_hints? : String = "",
) -> String {
  let result = StringBuilder()
  // File-level hints first, before the context
  if file_hints.length() > 0 {
    result.write_string(file_hints)
    result.write_string("\n\n")
  }
  // Surrounding lines in a code block
  let context_before = 2
  let context_after = 2
  let search_end = end_line.unwrap_or(start_line)
  let first_line = (start_line - context_before).max(1)
  let last_line = (search_end + context_after).min(
    total_line_count(content) + context_after,
  )
  result.write_string(
    "─── file context ───────────────────────────────\n",
  )
  result.write_string("```\n")
  for line_no in first_line..<=last_line {
    let ls = @line_offset.line_start_offset(content, line_no)
    let le = @line_offset.line_end_offset(content, line_no)
    let line_text = if le > ls && content[le - 1] == '\n' {
      content.unsafe_substring(start=ls, end=le - 1)
    } else {
      content.unsafe_substring(start=ls, end=le)
    }
    let gutter = if line_no >= start_line &&
      (end_line is None || line_no <= search_end) {
      " >"
    } else {
      "  "
    }
    result.write_string("\{gutter} \{line_no} | \{line_text}\n")
  }
  result.write_string("```\n")
  // First character difference
  let anchor_offset = @line_offset.line_start_offset(content, start_line)
  let compare_len = old_string.length().min(content.length() - anchor_offset)
  if compare_len > 0 {
    let actual = content.unsafe_substring(
      start=anchor_offset,
      end=anchor_offset + compare_len,
    )
    let diff_info = first_diff_info(old_string, actual)
    match diff_info {
      Some((pos, expected_char, actual_char)) => {
        let diff_pos = pos + 1
        result.write_string(
          "─── first difference ───────────────────────────\n",
        )
        result.write_string(
          "at character \{diff_pos}: expected `\{expected_char}`, got `\{actual_char}`",
        )
        // Specific diagnostics for common mismatch patterns
        if expected_char == "\n" && actual_char == "\r" {
          result.write_string(
            "\n— CRLF vs LF line-ending mismatch: the file uses `\\r\\n` (CRLF) but old_string uses `\\n` (LF); re-read the file to get the exact text",
          )
        } else if actual_char == "\r" &&
          pos + 1 < actual.length() &&
          actual[pos + 1] == '\n' {
          result.write_string(
            "\n— CRLF vs LF line-ending mismatch near this position; re-read the file to get the exact text",
          )
        } else if expected_char == "'" &&
          (actual_char == "\u{2018}" || actual_char == "\u{2019}") {
          result.write_string(
            "\n— curly vs straight single-quote mismatch: the file uses curly quotes (`'`/`'`), but models can only output straight quotes (`'`); re-read the file to get the exact text",
          )
        } else if expected_char == "\"" &&
          (actual_char == "\u{201C}" || actual_char == "\u{201D}") {
          result.write_string(
            "\n— curly vs straight double-quote mismatch: the file uses curly quotes (`\"`/`\"`), but models can only output straight quotes (`\"`); re-read the file to get the exact text",
          )
        }
        result.write_char('\n')
      }
      None => ()
    }
  } else {
    result.write_string(
      "─── first difference ───────────────────────────\n",
    )
    result.write_string("old_string extends past the end of the file\n")
  }
  result.write_string(
    "─── hint ───────────────────────────────────────\ncheck for CRLF vs LF line endings, tab vs space, full-width vs half-width characters, or a stray read-tool display separator (`|`) in old_string\n",
  )
  result.to_string()
}

///|
/// Find the first character where `expected` and `actual` differ.
/// Returns the position, the expected character, and the actual character.
fn first_diff_info(
  expected : String,
  actual : String,
) -> (Int, String, String)? {
  let len = expected.length().min(actual.length())
  for i in 0..<len {
    if expected[i] != actual[i] {
      return Some(
        (
          i,
          expected.unsafe_substring(start=i, end=i + 1),
          actual.unsafe_substring(start=i, end=i + 1),
        ),
      )
    }
  }
  if expected.length() != actual.length() {
    let pos = len
    let expected_str = if pos < expected.length() {
      expected.unsafe_substring(start=pos, end=pos + 1)
    } else {
      "∅"
    }
    let actual_str = if pos < actual.length() {
      actual.unsafe_substring(start=pos, end=pos + 1)
    } else {
      "∅"
    }
    return Some((pos, expected_str, actual_str))
  }
  None
}

///|
test "inserted_line_span counts the lines the insert occupies" {
  // Newline-terminated: one line per newline.
  assert_eq(inserted_line_span("a\n"), 1)
  assert_eq(inserted_line_span("a\nb\n"), 2)
  // A trailing fragment without a newline still occupies a (shared) line.
  assert_eq(inserted_line_span("a"), 1)
  assert_eq(inserted_line_span("a\nb"), 2)
}

///|
test "edit_reject_report excerpts the would-be content and asks for a re-issue" {
  let would_be =
    #|///|
    #|pub fn f() -> Int {
    #|  match 42 {
    #|}
  inspect(
    edit_reject_report(
      "lib/a.mbt",
      would_be,
      {
        errors: [
          {
            loc: "4:1-4:2",
            message: "Parse error, unexpected token `}`.",
            context: "",
          },
        ],
        truncated: false,
      },
      introduced=1,
      before_count=0,
    ),
    content=(
      #|rejected: the edit would introduce 1 new parse error(s) in lib/a.mbt, so the file was NOT modified.
      #|first 1 parse error(s), excerpted from the WOULD-BE content (not what is on disk):
      #|lib/a.mbt:4:1-4:2: Parse error, unexpected token `}`.
      #|  3 |  match 42 {
      #|  4 |}
      #|re-issue the edit with a corrected new_string (check delimiters against the excerpt above).
      #|(To intentionally produce content that does not parse, e.g. a fixture, pass revert_on_parse_errors=false.)
    ),
  )
}

///|
test "edit_reject_report pushes smaller edits and names pre-existing errors" {
  let errors = [
    for index in 0..<5 => {
      (
        { loc: "\{index + 1}:1", message: "e\{index}", context: "", } :
        @auto_check.ParseGateError)
    }
  ]
  let report = edit_reject_report(
    "lib/a.mbt",
    "a\nb\nc\nd\ne",
    { errors, truncated: false, },
    introduced=4,
    before_count=1,
  )
  assert_true(report.contains("4 new parse errors usually means"))
  assert_true(report.contains("split it into smaller pieces"))
  assert_true(report.contains("already has 1 parse error(s)"))
  assert_false(report.contains("re-issue the edit with a corrected new_string"))
  // A truncated capture reports a lower bound, never an exact count.
  let clipped = edit_reject_report(
    "lib/a.mbt",
    "a",
    { errors: [{ loc: "1:1", message: "e", context: "", }], truncated: true, },
    introduced=1,
    before_count=0,
  )
  assert_true(clipped.contains("would introduce at least 1 new parse error(s)"))
}

///|
test "preview_display_line truncates on a character boundary" {
  // short lines pass through untouched
  assert_eq(preview_display_line("plain"), "plain")
  // an over-long ASCII line keeps exactly the cap plus the ellipsis
  assert_eq(preview_display_line(String::make(250, 'x')).length(), 201)
  // an astral character straddling the cap is dropped whole, never split
  let straddling = "\{String::make(199, 'x')}😀tail"
  let cut = preview_display_line(straddling)
  assert_true(cut.has_suffix("…"))
  assert_false(cut.contains("😀"))
  assert_eq(cut.length(), 200)
}

///|
test "first_diff_info returns None for identical strings" {
  assert_eq(first_diff_info("hello", "hello"), None)
  assert_eq(first_diff_info("", ""), None)
  assert_eq(first_diff_info("a\nb", "a\nb"), None)
}

///|
test "first_diff_info finds first character difference" {
  guard first_diff_info("abc", "abd") is Some((pos, expected, actual)) else {
    fail("expected Some")
  }
  assert_eq(pos, 2)
  assert_eq(expected, "c")
  assert_eq(actual, "d")
}

///|
test "first_diff_info detects length mismatch" {
  // expected longer
  guard first_diff_info("abcd", "ab") is Some((pos, expected, actual)) else {
    fail("expected Some")
  }
  assert_eq(pos, 2)
  assert_eq(expected, "c")
  assert_eq(actual, "∅")
  // actual longer
  guard first_diff_info("ab", "abcd") is Some((pos2, expected2, actual2)) else {
    fail("expected Some")
  }
  assert_eq(pos2, 2)
  assert_eq(expected2, "∅")
  assert_eq(actual2, "c")
}

///|
test "first_diff_info detects tab vs space" {
  guard first_diff_info("\tindent", "  indent") is Some((pos, expected, actual)) else {
    fail("expected Some")
  }
  assert_eq(pos, 0)
  assert_eq(expected, "\t")
  assert_eq(actual, " ")
}

///|
test "first_diff_info detects CRLF vs LF" {
  guard first_diff_info("a\nb", "a\r\nb") is Some((pos, expected, actual)) else {
    fail("expected Some")
  }
  assert_eq(pos, 1)
  assert_eq(expected, "\n")
  assert_eq(actual, "\r")
}

///|
test "old_string_context clamps last_line to end of file" {
  let content = "a\nb\nc\n"
  let ctx = old_string_context(content, "x", 1, Some(999999))
  // Should not loop 1M times; last_line clamped to 5 (3 file lines + 2 context_after)
  assert_true(ctx.contains("─── file context"))
  assert_true(ctx.contains("─── hint"))
  // All 3 file lines should appear; no error from past-EOF iteration
  assert_true(ctx.contains("1 | a"))
  assert_true(ctx.contains("2 | b"))
  assert_true(ctx.contains("3 | c"))
}

///|
test "old_string_context shows context lines and first difference" {
  let content = "alpha\nbeta\ngamma\n"
  let ctx = old_string_context(content, "delta", 2, None)
  // Shows surrounding lines
  assert_true(ctx.contains("1 | alpha"))
  assert_true(ctx.contains("> 2 | beta"))
  assert_true(ctx.contains("3 | gamma"))
  // First difference at char 1: expected 'd', got 'b'
  assert_true(ctx.contains("expected `d`"))
  assert_true(ctx.contains("got `b`"))
  // Hint always present
  assert_true(ctx.contains("CRLF vs LF"))
}

///|
test "old_string_context shows empty suffix for past-EOF context" {
  let content = "single\n"
  let ctx = old_string_context(content, "x", 1, None)
  // Line 2 and 3 exist as past-EOF context (empty lines)
  assert_true(ctx.contains("1 | single"))
  assert_true(ctx.contains("2 |"))
  assert_true(ctx.contains("3 |"))
}

///|
test "normalize_content_for_matching preserves LF-only content unchanged" {
  let (norm, map) = @matching.normalize_content_for_matching("a\nb\nc")
  assert_eq(norm, "a\nb\nc")
  assert_eq(map, [0, 1, 2, 3, 4])
}

///|
test "normalize_content_for_matching converts CRLF to LF and builds correct offset map" {
  let (norm, map) = @matching.normalize_content_for_matching("a\r\nb\r\nc")
  assert_eq(norm, "a\nb\nc")
  // Each CRLF pair maps to a single \n in the normalized output
  // map[i] = original position of normalized character i
  assert_eq(map, [0, 1, 3, 4, 6])
}

///|
test "normalize_content_for_matching handles mixed CRLF and LF" {
  let (norm, map) = @matching.normalize_content_for_matching("a\r\nb\nc\r\n")
  assert_eq(norm, "a\nb\nc\n")
  assert_eq(map, [0, 1, 3, 4, 5, 6])
}

///|
test "normalize_content_for_matching handles empty and CRLF-only content" {
  let (norm, map) = @matching.normalize_content_for_matching("")
  assert_eq(norm, "")
  assert_eq(map, [])
  let (norm2, map2) = @matching.normalize_content_for_matching("\r\n")
  assert_eq(norm2, "\n")
  assert_eq(map2, [0])
}

///|
test "normalize_quotes leaves straight quotes unchanged" {
  assert_eq(@matching.normalize_quotes("hello 'world'"), "hello 'world'")
  assert_eq(@matching.normalize_quotes("hello \"world\""), "hello \"world\"")
  assert_eq(@matching.normalize_quotes(""), "")
}

///|
test "normalize_quotes converts curly quotes to straight quotes" {
  assert_eq(
    @matching.normalize_quotes("hello \u{2018}world\u{2019}"),
    "hello 'world'",
  )
  assert_eq(
    @matching.normalize_quotes("hello \u{201C}world\u{201D}"),
    "hello \"world\"",
  )
  assert_eq(
    @matching.normalize_quotes("\u{2018}a\u{2019} \u{201C}b\u{201D}"),
    "'a' \"b\"",
  )
}

///|
test "find_quote_normalized_match finds exact match" {
  let body = "hello world"
  assert_eq(@matching.find_quote_normalized_match(body, "world"), Some(6))
}

///|
test "find_quote_normalized_match matches curly quotes in body" {
  let body = "hello \u{2018}world\u{2019}"
  // Model sends straight quotes, file has curly quotes
  let result = @matching.find_quote_normalized_match(body, "hello 'world'")
  assert_eq(result, Some(0))
}

///|
test "find_quote_normalized_match matches curly quotes in needle" {
  let body = "hello 'world'"
  let result = @matching.find_quote_normalized_match(
    body, "hello \u{2018}world\u{2019}",
  )
  assert_eq(result, Some(0))
}

///|
test "find_quote_normalized_match returns None for no match" {
  assert_eq(@matching.find_quote_normalized_match("abc", "xyz"), None)
  assert_eq(@matching.find_quote_normalized_match("", "x"), None)
}

///|
test "has_crlf detects CRLF content" {
  assert_true(@matching.has_crlf("a\r\nb"))
  assert_false(@matching.has_crlf("a\nb"))
  assert_false(@matching.has_crlf(""))
}

///|
test "has_curly_quotes detects curly quotes" {
  assert_true(@matching.has_curly_quotes("\u{2018}hello\u{2019}"))
  assert_true(@matching.has_curly_quotes("\u{201C}hello\u{201D}"))
  assert_false(@matching.has_curly_quotes("'hello'"))
  assert_false(@matching.has_curly_quotes(""))
}
