///|
/// Tool definition for `multi_edit`: applies many exact line-anchored
/// replacements across one or more files after validating every edit against
/// the original file content.
///
/// `multi_edit` is the efficient path for compiler-feedback repair loops: when
/// diagnostics identify several known locations, batch every fix into one call
/// instead of many separate `edit` calls. Each edit names its own `file`, so a
/// single batch can span multiple files; all edits for a given file must be
/// listed contiguously.
pub fn definition(
  workspace_root? : String = ".",
  file_state? : @agent_tool.FileStateMap = @agent_tool.FileStateMap::new(),
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="multi_edit",
    description="Apply many exact line-anchored replacements across one or more files in a single validated batch — the efficient path for compiler-feedback repair: when `moon check` (or another analyzer) reports several known locations, fix them all in one call instead of many separate `edit` calls. Supply the edits two ways and either or both are used (they are concatenated): `edits` is an inline array of edit objects; `edits_file` is the path to a JSON file holding an array of the same objects — for large batches, generate that file from compiler diagnostics with a script and pass its path. Each edit is {file, old_string, new_string, start_line, optional end_line}: `file` is the path to change; `start_line` (1-based) anchors the search and `end_line` bounds it, so old_string can be the small exact span instead of a large context block; each edit replaces the first matching span in its range. Make old_string uniquely identify the flagged code — include the receiver, e.g. `args.length()` — so a rename cannot stray onto a same-named call elsewhere on the line. List all edits for a given file contiguously. To INSERT instead of replace, set old_string to the empty string: new_string is inserted at the start of start_line (any start_line past the last line appends at end of file — e.g. 999999; in MoonBit top-level order does not matter, so append new functions and tests at end of file rather than inserting mid-file). Combine changes on the same line (or one tight span) into a single edit, because adjacent or overlapping edits collide and the whole batch is rejected. Every edit is validated against the original files before anything is written; a batch that would introduce lex/parse errors into a .mbt file is also rejected BEFORE writing (see revert_on_parse_errors); if any edit fails, no files are changed.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "edits": {
          "type": "array",
          "description": "Edit objects applied inline. Concatenated with edits_file when both are given.",
          "items": {
            "type": "object",
            "properties": {
              "file": { "type": "string" },
              "old_string": { "type": "string" },
              "new_string": { "type": "string" },
              "start_line": { "type": "integer" },
              "end_line": { "type": "integer" },
            },
            "required": ["file", "old_string", "new_string", "start_line"],
          },
          "examples": [
            [
              {
                "file": "lib/parser.mbt",
                "old_string": "args.length()",
                "new_string": "args.len()",
                "start_line": 12,
              },
            ],
          ],
        },
        "edits_file": {
          "type": "string",
          "description": "Path to a JSON file holding an array of the same edit objects — a response file for large, script-generated batches. Concatenated with inline edits when both are given.",
          "examples": ["fixes.json"],
        },
        "revert_when_errors_above": {
          "type": "integer",
          "description": "Auto-revert safety net. After the batch is written, `moon check` runs; if this batch INTRODUCES more than this many new compile errors (measured against the pre-batch error count, so pre-existing errors and all warnings are ignored), the entire batch is rolled back to its pre-batch contents and the call returns an error listing the first few new errors — so an over-matching replace cannot leave a broken tree to untangle. Default 5; the host caps the effective value (you can make it stricter, e.g. 0 to revert on any new error, but cannot disable it). A batch that keeps or reduces the error count is never reverted.",
          "examples": [5],
        },
        "revert_on_parse_errors": {
          "type": "boolean",
          "description": "Syntax gate, on by default. Before the batch is written, each edited syntax-checkable file's (.mbt, .mbt.md, moon.mod, moon.pkg) rendered result is parsed standalone (moonc syncheck); if any file would gain new lex/parse errors — measured against its pre-batch content parsed the same way, so pre-existing parse errors are ignored — the WHOLE batch is rejected with no files changed, and the call returns the errors with excerpts of the would-be content. Type errors never trigger this gate (the post-write revert_when_errors_above guard covers those); in .mbt.md only the checked (`mbt check` / `moonbit check`) fenced blocks are parsed. Set false only to intentionally produce content that does not parse (e.g. a fixture).",
          "examples": [false],
        },
      },
    }),
    execute=Async(arguments => {
      execute_with_workspace(workspace_root, file_state, arguments)
    }),
  )
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
) -> @agent_tool.ToolAction {
  let args = @decode.decode_args(arguments) catch {
    error =>
      return @agent_tool.ToolAction::respond(
        "error: multi_edit requires \{@tool_error.failure_message("\{error}")}",
        is_error=true,
      )
  }
  // Concatenate the inline edits with the response file's edits (inline first).
  let edits = args.inline
  if args.edits_file is Some(spec) {
    match load_edits_file(workspace_root, spec) {
      Ok(file_edits) => edits.append(file_edits)
      Err(action) => return action
    }
  }
  if edits.is_empty() {
    return @agent_tool.ToolAction::respond(
      "error: multi_edit requires edits and/or edits_file (no edits were provided)",
      is_error=true,
    )
  }
  multi_edit_files(
    workspace_root,
    edits,
    args.revert_when_errors_above,
    revert_on_parse_errors=args.revert_on_parse_errors,
    file_state~,
  )
}

///|
/// Read and parse an `edits file` spec. Returns the decoded edits, or a ready
/// error response describing why the spec could not be loaded. The spec's
/// top-level JSON is the same array of edit objects accepted inline.
async fn load_edits_file(
  workspace_root : String,
  spec : String,
) -> Result[Array[@decode.MultiEditItem], @agent_tool.ToolAction] {
  let brief = "multi_edit"
  let path = @workspace_path.resolve(workspace_root, spec)
  let text = @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      return Err(
        @agent_tool.ToolAction::respond(
          "error: multi_edit could not read edits file \{path}: \{error}",
          is_error=true,
          brief~,
        ),
      )
  }
  let json = @json.parse(text) catch {
    error =>
      return Err(
        @agent_tool.ToolAction::respond(
          "error: multi_edit edits file \{path} is not valid JSON: \{error}",
          is_error=true,
          brief~,
        ),
      )
  }
  let edits = @decode.decode_edits_json(json) catch {
    error =>
      return Err(
        @agent_tool.ToolAction::respond(
          "error: multi_edit requires \{@tool_error.failure_message("\{error}")} in edits file \{path}",
          is_error=true,
          brief~,
        ),
      )
  }
  Ok(edits)
}

///|
/// A file's edits already validated and rendered, ready to write. Built only
/// after the whole batch has passed validation, so a write is the last step.
priv struct PreparedWrite {
  path : String
  new_content : String
  // The file's pre-batch content, kept so the auto-revert guard can roll the
  // file back (and re-measure the baseline error count) without re-reading.
  original_content : String
  edit_count : Int
}

///|
/// A file whose edits all validated. `file` is the spelling the caller used
/// (for messages); `path` is the resolved location (the grouping key and the
/// write target).
priv struct PreparedFile {
  file : String
  path : String
  content : String
  plans : Array[PlannedEdit]
}

///|
/// Apply a validated batch across one or more files. Validation runs over every
/// file first; if any edit fails (or any file can't be read or is write-guarded)
/// nothing is written. Writes happen only once the entire batch is clean, which
/// keeps partial application limited to a raw filesystem write error.
async fn multi_edit_files(
  workspace_root : String,
  edits : Array[@decode.MultiEditItem],
  revert_when_errors_above : Int?,
  revert_on_parse_errors~ : Bool,
  file_state~ : @agent_tool.FileStateMap,
) -> @agent_tool.ToolAction {
  let brief = "multi_edit"
  // Resolve every edit's path up front and key contiguity and grouping on the
  // resolved path, so two spellings of one file (e.g. `a.mbt` and `./a.mbt`)
  // collapse into a single group rather than racing each other's writes.
  let resolved = [
    for index, item in edits => {
      (
        {
          index,
          file: item.file,
          path: @workspace_path.resolve(workspace_root, item.file),
          item,
        } : ResolvedEdit)
    }
  ]
  // A file's edits must form one contiguous block so each file is read,
  // validated, and written exactly once.
  if check_contiguity(resolved) is Some(message) {
    return @agent_tool.ToolAction::respond(message, is_error=true, brief~)
  }
  let groups = group_contiguous(resolved)
  let failures : Array[EditFailure] = []
  let prepared : Array[PreparedFile] = []
  for group in groups {
    let content = @fs.read_file(group.path).text() catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        failures.push({
          file: group.file,
          index: None,
          range: "",
          message: "error reading file: \{error}",
        })
        continue
      }
    }
    let plans : Array[PlannedEdit] = []
    for edit in group.items {
      match validate_edit(content, edit.item, edit.index, file=group.file) {
        Valid(plan) => plans.push(plan)
        Invalid(failure) => failures.push(failure)
      }
    }
    collect_overlap_failures(group.file, plans, failures)
    prepared.push({ file: group.file, path: group.path, content, plans })
  }
  if failures.length() > 0 {
    return @agent_tool.ToolAction::respond(
      failure_report(failures),
      is_error=true,
      brief~,
    )
  }
  // Render each file and run the write guard before touching disk, so a guarded
  // path aborts the whole batch instead of leaving earlier files written.
  let writes : Array[PreparedWrite] = []
  for prepared_file in prepared {
    let new_content = apply_plans(prepared_file.content, prepared_file.plans)
    match @manifest_error.write_error(prepared_file.path, new_content) {
      Some(message) =>
        failures.push({
          file: prepared_file.file,
          index: None,
          range: "",
          message,
        })
      None =>
        writes.push({
          path: prepared_file.path,
          new_content,
          original_content: prepared_file.content,
          edit_count: prepared_file.plans.length(),
        })
    }
  }
  if failures.length() > 0 {
    return @agent_tool.ToolAction::respond(
      failure_report(failures),
      is_error=true,
      brief~,
    )
  }
  // Pre-write syntax gate over the rendered batch (see parse_gate.mbt): if
  // any edited `.mbt` file would gain new lex/parse errors, reject the whole
  // batch before anything touches disk — the same all-or-nothing contract as
  // the validation above. Type-error regressions stay the post-write
  // moon-check guard's job below.
  if revert_on_parse_errors &&
    parse_gate_batch_rejection(writes) is Some(rejection) {
    return rejection
  }
  for write in writes {
    @fs.write_file(write.path, write.new_content, create_mode=CreateOrTruncate) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        return @agent_tool.ToolAction::respond(
          "error multi_editing \{write.path}: error writing file: \{error}; earlier files in the batch may already be written",
          is_error=true,
          brief~,
        )
    }
    // multi_edit only rewrites files it read, so each is a modification (never
    // a create). record_modified preserves a stronger `Created` state if the
    // agent created this file earlier this session. A later auto-revert may
    // restore the content, but the tool did write the path this session.
    file_state.record_modified(write.path)
  }
  // The batch is on disk. Run the auto-revert guard from the first written
  // file's module: it appends `moon check` feedback and, if this batch
  // introduced too many new errors, rolls the whole batch back. A batch
  // spanning multiple modules only checks the first module's diagnostics, which
  // is acceptable for the in-project repair case. `writes` is non-empty here (a
  // non-empty batch with no failures always renders at least one write), but
  // match defensively rather than index blindly.
  match writes.get(0) {
    Some(first) =>
      revert_guarded_response(
        first.path,
        writes,
        effective_revert_threshold(revert_when_errors_above),
      )
    None =>
      @agent_tool.ToolAction::respond(
        success_summary(writes),
        brief=success_brief(writes),
      )
  }
}

///|
/// How many offending files a batch reject report details in full; the rest
/// are named in a summary line so a wide batch cannot flood the transcript.
const RejectedFileDisplayLimit : Int = 3

///|
/// One file the parse gate rejected: how many new parse errors the batch
/// would introduce there, and the formatted excerpts.
priv struct FileRejection {
  path : String
  introduced : Int
  truncated : Bool
  section : String
}

///|
/// Pre-write syntax gate over the rendered batch: parse each edited syncheck
/// input's would-be result standalone (moonc syncheck, see parse_gate.mbt) and
/// reject the whole batch when any file would gain new parse errors versus its
/// pre-batch content parsed the same way. The same soundness rules as `edit`'s
/// gate apply per file: fail open when the gate cannot run or the baseline is
/// missing/truncated, accept a truncated new-content capture as a lower bound,
/// and resolve symlinked targets before deciding whether a file is gateable.
async fn parse_gate_batch_rejection(
  writes : Array[PreparedWrite],
) -> @agent_tool.ToolAction? {
  let rejections : Array[FileRejection] = []
  for write in writes {
    let target = @fs.realpath(write.path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => write.path
    }
    // Gate under every syncheck kind this file could be classified as. A
    // regular file yields one kind; a symlink that crosses kinds (e.g.
    // `link.mbt -> doc.mbt.md`) yields two, and moon's classification of such a
    // link is ambiguous, so check both and reject on the first that regresses.
    // See `gate_paths`.
    for gate_path in @auto_check.gate_paths(write.path, target) {
      let gate = @auto_check.content_parse_errors(gate_path, write.new_content) catch {
        error if @async.is_being_cancelled() => raise error
        _ => None
      }
      guard gate is Some(gate) && gate.errors.length() > 0 else { continue }
      let before = @auto_check.content_parse_errors(
        gate_path,
        write.original_content,
      ) catch {
        error if @async.is_being_cancelled() => raise error
        _ => None
      }
      guard before is Some(before) && !before.truncated else { continue }
      let before_count = before.errors.length()
      let introduced = gate.errors.length() - before_count
      if introduced <= 0 {
        continue
      }
      let bound = if gate.truncated { "at least " } else { "" }
      let pre_existing = if before_count > 0 {
        " (already has \{before_count} parse error(s); excerpts may include pre-existing ones)"
      } else {
        ""
      }
      let formatted = @auto_check.format_parse_gate_errors(
        write.path,
        write.new_content,
        gate.errors,
      )
      rejections.push({
        path: write.path,
        introduced,
        truncated: gate.truncated,
        section: "\{write.path}: would gain \{bound}\{introduced} new parse error(s)\{pre_existing}:\n\{formatted.join("\n")}",
      })
      // One rejection per file: the first kind that regresses is enough.
      break
    }
  }
  if rejections.is_empty() {
    return None
  }
  let total = rejections.fold(init=0, (total, rejection) => {
    total + rejection.introduced
  })
  let any_truncated = rejections.any(rejection => rejection.truncated)
  let bound = if any_truncated { "≥" } else { "" }
  Some(
    @agent_tool.ToolAction::respond(
      batch_reject_report(rejections, total~, any_truncated~),
      is_error=true,
      brief="multi_edit rejected (\{bound}\{total} parse error(s))",
    ),
  )
}

///|
/// The rejected-batch report: no files were changed, per-file excerpts of the
/// would-be content (capped), and how to retry.
fn batch_reject_report(
  rejections : Array[FileRejection],
  total~ : Int,
  any_truncated~ : Bool,
) -> String {
  let total_label = if any_truncated { "at least \{total}" } else { "\{total}" }
  let head = "rejected: the batch would introduce \{total_label} new parse error(s) across \{rejections.length()} file(s), so NO files were changed."
  let shown = rejections.length().min(RejectedFileDisplayLimit)
  let sections = [ for rejection in rejections[0:shown] => rejection.section ]
  let overflow = if rejections.length() > shown {
    let hidden = [ for rejection in rejections[shown:] => rejection.path ]
    "\n…and \{hidden.length()} more file(s): \{hidden.join(", ")}"
  } else {
    ""
  }
  let retry = "\nre-issue with corrected new_strings (check delimiters against the excerpts above), or split the batch and check after each step."
  let opt_out = "\n(To intentionally produce content that does not parse, e.g. a fixture, pass revert_on_parse_errors=false.)"
  "\{head}\nexcerpts are from the WOULD-BE content (not what is on disk):\n\{sections.join("\n")}\{overflow}\{retry}\{opt_out}"
}

///|
/// The host default number of newly introduced errors a batch may cause before
/// it is auto-reverted. Conservative: a handful of new errors is a likely
/// over-match, not a transient cross-file gap.
const DefaultRevertThreshold : Int = 5

///|
/// The largest threshold the model may request. The model can make the guard
/// stricter (down to 0 — revert on any new error) but never raise it past this
/// cap, so an overconfident call cannot silently disable the safety net.
const HostMaxRevertThreshold : Int = 10

///|
/// Resolve the model's requested threshold against the host policy: absent →
/// the default; present → clamped to `[0, HostMaxRevertThreshold]`.
fn effective_revert_threshold(requested : Int?) -> Int {
  match requested {
    Some(value) => value.clamp(min=0, max=HostMaxRevertThreshold)
    None => DefaultRevertThreshold
  }
}

///|
/// Run `moon check` over the just-written batch and decide whether to keep it
/// or roll it back. Keeps the batch (reporting honestly when sub-threshold
/// errors remain) unless it introduced more than `threshold` NEW errors versus
/// the pre-batch baseline; the baseline is measured lazily — only when the
/// after-check already breaches the threshold — by restoring the originals,
/// re-checking, then either staying reverted or re-applying.
async fn revert_guarded_response(
  check_path : String,
  writes : Array[PreparedWrite],
  threshold : Int,
) -> @agent_tool.ToolAction {
  let summary = success_summary(writes)
  let kept = @agent_tool.ToolAction::respond(
    summary,
    brief=success_brief(writes),
  )
  let after = count_errors_or_none(check_path)
  // Not a MoonBit project, or the check could not run: keep the batch exactly
  // as applied, just as before this guardrail existed.
  guard after is Some(after) else { return kept }
  if after.error_count <= threshold {
    return @agent_tool.ToolAction::respond(
      keep_response(summary, after, threshold),
      brief=success_brief(writes),
    )
  }
  // Suspicious: the post-batch error count is over the line. Measure the
  // pre-batch baseline by restoring the originals and re-checking, so the guard
  // fires on errors this batch INTRODUCED, not on ones that were already there.
  let restore_failures = write_files(writes, write => write.original_content)
  let before = count_errors_or_none(check_path)
  let before_count = match before {
    Some(before) => before.error_count
    None => 0
  }
  let introduced = after.error_count - before_count
  if introduced > threshold {
    // Real breakage. Stay reverted (the originals are already back on disk).
    @agent_tool.ToolAction::respond(
      revert_report(writes, after, introduced~, threshold~, restore_failures~),
      is_error=true,
      brief="multi_edit reverted (\{introduced} new error(s))",
    )
  } else {
    // False alarm: the errors were mostly pre-existing. Re-apply and keep.
    let _ = write_files(writes, write => write.new_content)
    @agent_tool.ToolAction::respond(
      keep_response(summary, after, threshold, introduced~),
      brief=success_brief(writes),
    )
  }
}

///|
/// `@auto_check.count_errors`, with cancellation propagated and any other
/// failure mapped to `None` (fail open — keep the batch unguarded).
async fn count_errors_or_none(path : String) -> @auto_check.CheckErrors? {
  @auto_check.count_errors(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
/// Write `content(write)` to every file, returning the paths that could not be
/// written (best effort — a restore/re-apply must not raise mid-rollback). A
/// non-empty result is surfaced in the revert report so a half-restored tree is
/// never reported as a clean rollback.
async fn write_files(
  writes : Array[PreparedWrite],
  content : (PreparedWrite) -> String,
) -> Array[String] {
  let failures : Array[String] = []
  for write in writes {
    @fs.write_file(write.path, content(write), create_mode=CreateOrTruncate) catch {
      error if @async.is_being_cancelled() => raise error
      _ => failures.push(write.path)
    }
  }
  failures
}

///|
/// The kept-batch response: the success summary plus an honest `moon check`
/// status line. A batch that still leaves errors is reported as `applied with
/// N error(s)`, never as clean. `introduced` is `Some` only on the rare
/// false-alarm path where the post-batch count breached the threshold but the
/// batch turned out to add few NEW errors (most pre-existed) — then the line
/// makes the introduced-vs-total split explicit, so a kept total above the
/// threshold never reads as a contradiction.
fn keep_response(
  summary : String,
  after : @auto_check.CheckErrors,
  threshold : Int,
  introduced? : Int,
) -> String {
  if after.error_count == 0 {
    return "\{summary}\nmoon check: ok — 0 errors, \{after.warning_count} warning(s)"
  }
  let errors = error_count_label(after)
  let header = match introduced {
    Some(introduced) =>
      "\{summary}\nmoon check: applied with \{errors} error(s) kept (only \{introduced} newly introduced ≤ revert_when_errors_above=\{threshold}; the rest pre-existed), \{after.warning_count} warning(s)"
    None =>
      "\{summary}\nmoon check: applied with \{errors} error(s) kept (≤ revert_when_errors_above=\{threshold}), \{after.warning_count} warning(s)"
  }
  if after.first_errors.is_empty() {
    header
  } else {
    "\{header}\n\{after.first_errors.join("\n")}"
  }
}

///|
/// The reverted-batch report: what was applied, how many new errors triggered
/// the rollback, the first few of them, and how to retry.
fn revert_report(
  writes : Array[PreparedWrite],
  after : @auto_check.CheckErrors,
  introduced~ : Int,
  threshold~ : Int,
  restore_failures~ : Array[String],
) -> String {
  let total = total_edit_count(writes)
  let head = "reverted: applied \{total} edit(s) across \{writes.length()} file(s), but moon check then reported \{error_count_label(after)} error(s) (\{introduced} newly introduced > revert_when_errors_above=\{threshold}); all \{writes.length()} file(s) were rolled back to their pre-batch contents."
  let errors = if after.first_errors.is_empty() {
    ""
  } else {
    "\nfirst \{after.first_errors.length()} error(s):\n\{after.first_errors.join("\n")}"
  }
  let restore_note = if restore_failures.is_empty() {
    ""
  } else {
    "\nWARNING: could not restore \{restore_failures.length()} file(s): \{restore_failures.join(", ")} — inspect them manually."
  }
  let tail = "\nre-issue with more precise old_strings (include the receiver) and/or smaller batches so a replacement cannot stray onto unintended sites."
  "\{head}\{errors}\{restore_note}\{tail}"
}

///|
/// Render an error count, marking it a lower bound when moon check's output was
/// truncated (so the true count is at least this many).
fn error_count_label(after : @auto_check.CheckErrors) -> String {
  if after.truncated {
    "≥\{after.error_count}"
  } else {
    "\{after.error_count}"
  }
}

///|
/// Reject a batch where a file's edits are not contiguous: once a file's block
/// ends, that file must not reappear. Returns an error message, or `None` when
/// every file occupies a single run.
fn check_contiguity(edits : Array[ResolvedEdit]) -> String? {
  // Set of paths whose contiguous block has already ended, so the membership
  // test stays O(1) even for a large batch touching many files.
  let ended : Map[String, Unit] = Map([])
  let mut current : String? = None
  for edit in edits {
    let same = current is Some(path) && path == edit.path
    if !same {
      if ended.contains(edit.path) {
        return Some(
          "error multi_editing: edits for \{edit.file} must be contiguous; it reappears at edit[\{edit.index}] after another file's edits; list all edits for a file together",
        )
      }
      if current is Some(path) {
        ended[path] = ()
      }
      current = Some(edit.path)
    }
  }
  None
}

///|
/// One decoded edit with its position in the original batch and its resolved
/// path. `index` lets failures point the model back at `edit[index]`; `path` is
/// the grouping key so aliased spellings of one file land together.
priv struct ResolvedEdit {
  index : Int
  file : String
  path : String
  item : @decode.MultiEditItem
}

///|
/// A contiguous run of edits that all target the same resolved file.
priv struct FileGroup {
  file : String
  path : String
  items : Array[ResolvedEdit]
}

///|
/// Group edits into per-file runs keyed on the resolved path. Contiguity is
/// already guaranteed by `check_contiguity`, so a file extends only the most
/// recent group.
fn group_contiguous(edits : Array[ResolvedEdit]) -> Array[FileGroup] {
  let groups : Array[FileGroup] = []
  for edit in edits {
    let count = groups.length()
    if count > 0 && groups[count - 1].path == edit.path {
      groups[count - 1].items.push(edit)
    } else {
      groups.push({ file: edit.file, path: edit.path, items: [edit] })
    }
  }
  groups
}

///|
/// Total number of edits applied across a batch's writes.
fn total_edit_count(writes : Array[PreparedWrite]) -> Int {
  writes.fold(init=0, (total, write) => total + write.edit_count)
}

///|
fn success_summary(writes : Array[PreparedWrite]) -> String {
  let total = total_edit_count(writes)
  let lines = [
    for write in writes => "\{write.path}: \{write.edit_count} edit(s)"
  ]
  "ok: applied \{total} edit(s) across \{writes.length()} file(s)\n\{lines.join("\n")}"
}

///|
fn success_brief(writes : Array[PreparedWrite]) -> String {
  let total = total_edit_count(writes)
  if writes.length() == 1 {
    "multi_edit \{@agent_tool.brief_basename(writes[0].path)} (\{total}×)"
  } else {
    "multi_edit \{writes.length()} files (\{total}×)"
  }
}

///|
priv enum EditValidation {
  Valid(PlannedEdit)
  Invalid(EditFailure)
}

///|
priv struct PlannedEdit {
  index : Int
  start : Int
  end : Int
  new_string : String
  range : String
}

///|
/// A rejected edit (or a file-level read/write-guard problem, when `index` is
/// `None`). `file` lets the report point at the right file in a multi-file batch.
priv struct EditFailure {
  file : String
  index : Int?
  range : String
  message : String
}

///|
fn validate_edit(
  content : String,
  item : @decode.MultiEditItem,
  index : Int,
  file~ : String,
) -> EditValidation {
  let range = line_range_label(item.start_line, item.end_line)
  if item.old_string == "" {
    // Insertion: an empty old_string inserts new_string at the start of
    // start_line (a zero-width edit). Any start_line past the last line clamps
    // to end of file, so a large value appends. end_line is ignored for
    // insertion.
    if item.new_string == "" {
      return Invalid({
        file,
        index: Some(index),
        range,
        message: "old_string and new_string are both empty",
      })
    }
    let at = line_start_offset(content, item.start_line).clamp(
      min=0,
      max=content.length(),
    )
    return Valid({
      index,
      start: at,
      end: at,
      new_string: item.new_string,
      range,
    })
  }
  if item.old_string == item.new_string {
    return Invalid({
      file,
      index: Some(index),
      range,
      message: "old_string and new_string are identical",
    })
  }
  let region = select_edit_region(content, item.start_line, item.end_line)
  guard region.body.find(item.old_string) is Some(offset) else {
    return Invalid({
      file,
      index: Some(index),
      range,
      message: "old_string not found",
    })
  }
  let start = region.start_offset + offset
  Valid({
    index,
    start,
    end: start + item.old_string.length(),
    new_string: item.new_string,
    range,
  })
}

///|
fn collect_overlap_failures(
  file : String,
  plans : Array[PlannedEdit],
  failures : Array[EditFailure],
) -> Unit {
  let ordered = plans.copy()
  ordered.sort_by(compare_plan_ascending)
  let mut previous_end = -1
  let mut previous_index = -1
  for plan in ordered {
    if plan.start < previous_end {
      failures.push({
        file,
        index: Some(plan.index),
        range: plan.range,
        message: "replacement overlaps edit[\{previous_index}]",
      })
    }
    if plan.end > previous_end {
      previous_end = plan.end
      previous_index = plan.index
    }
  }
}

///|
fn compare_plan_ascending(a : PlannedEdit, b : PlannedEdit) -> Int {
  (a.start, a.end, a.index).compare((b.start, b.end, b.index))
}

///|
fn compare_plan_descending(a : PlannedEdit, b : PlannedEdit) -> Int {
  -compare_plan_ascending(a, b)
}

///|
fn apply_plans(content : String, plans : Array[PlannedEdit]) -> String {
  let ordered = plans.copy()
  ordered.sort_by(compare_plan_descending)
  let mut output = content
  for plan in ordered {
    output = "\{output.unsafe_substring(start=0, end=plan.start)}\{plan.new_string}\{output.unsafe_substring(start=plan.end, end=output.length())}"
  }
  output
}

///|
fn failure_report(failures : Array[EditFailure]) -> String {
  let lines = [ for failure in failures => format_failure(failure) ]
  "error multi_editing: \{failures.length()} problem(s); no changes applied\n\{lines.join("\n")}"
}

///|
fn format_failure(failure : EditFailure) -> String {
  match failure.index {
    Some(index) =>
      "\{failure.file} edit[\{index}] \{failure.range}: \{failure.message}"
    None => "\{failure.file}: \{failure.message}"
  }
}

///|
priv struct EditRegion {
  body : String
  start_offset : Int
}

///|
fn select_edit_region(
  content : String,
  start_line : Int,
  end_line : Int?,
) -> EditRegion {
  let start = line_start_offset(content, start_line)
  let end = match end_line {
    Some(line) => line_end_offset(content, line)
    None => content.length()
  }
  let start = start.clamp(min=0, max=content.length())
  let end = end.clamp(min=start, max=content.length())
  { body: content.unsafe_substring(start~, end~), start_offset: start }
}

///|
fn line_start_offset(content : String, line : Int) -> Int {
  // Line `line` starts right after line `line - 1` ends (nobreak: both scans
  // land on content.length() for a line past EOF).
  if line <= 1 {
    0
  } else {
    line_end_offset(content, line - 1)
  }
}

///|
fn line_end_offset(content : String, line : Int) -> Int {
  let len = content.length()
  let mut current_line = 1
  for cursor in 0..<len {
    if content[cursor] == '\n' {
      if current_line == line {
        break cursor + 1
      }
      current_line = current_line + 1
    }
  } nobreak {
    len
  }
}

///|
fn line_range_label(start_line : Int, end_line : Int?) -> String {
  match end_line {
    Some(end) => "line range \{start_line}-\{end}"
    None => "from line \{start_line}"
  }
}

///|
/// White-box tests for the auto-revert guard's pure pieces: threshold policy
/// and the two report formatters. The end-to-end revert (which runs a real
/// `moon check`) is exercised by the A/B harness, not here.

///|
fn sample_write(path : String, edits : Int) -> PreparedWrite {
  { path, new_content: "new", original_content: "old", edit_count: edits }
}

///|
test "effective_revert_threshold defaults and clamps to the host policy" {
  // Absent → host default.
  assert_eq(effective_revert_threshold(None), DefaultRevertThreshold)
  // The model may tighten the guard, down to 0 (revert on any new error).
  assert_eq(effective_revert_threshold(Some(2)), 2)
  assert_eq(effective_revert_threshold(Some(0)), 0)
  // A negative request is floored at 0, not treated as "disable".
  assert_eq(effective_revert_threshold(Some(-3)), 0)
  // The model cannot raise the guard past the host cap.
  assert_eq(
    effective_revert_threshold(Some(HostMaxRevertThreshold + 50)),
    HostMaxRevertThreshold,
  )
}

///|
test "keep_response is clean at zero errors and honest below threshold" {
  let summary = "ok: applied 3 edit(s) across 1 file(s)\na.mbt: 3 edit(s)"
  let clean : @auto_check.CheckErrors = {
    error_count: 0,
    warning_count: 12,
    first_errors: [],
    truncated: false,
  }
  assert_eq(
    keep_response(summary, clean, 5),
    "\{summary}\nmoon check: ok — 0 errors, 12 warning(s)",
  )
  let kept : @auto_check.CheckErrors = {
    error_count: 2,
    warning_count: 12,
    first_errors: ["a.mbt:1:1-1:2: boom", "a.mbt:4:1-4:2: bang"],
    truncated: false,
  }
  assert_eq(
    keep_response(summary, kept, 5),
    "\{summary}\nmoon check: applied with 2 error(s) kept (≤ revert_when_errors_above=5), 12 warning(s)\na.mbt:1:1-1:2: boom\na.mbt:4:1-4:2: bang",
  )
}

///|
test "keep_response on the false-alarm path makes the introduced split explicit" {
  let summary = "ok: applied 3 edit(s) across 1 file(s)\na.mbt: 3 edit(s)"
  // Baseline already had 7 errors; the batch kept it at 8 (1 newly introduced),
  // which is ≤ threshold even though the 8 total is above it. The line must not
  // claim "8 ≤ 5"; it states the 1 introduced instead.
  let after : @auto_check.CheckErrors = {
    error_count: 8,
    warning_count: 0,
    first_errors: ["a.mbt:1:1-1:2: boom"],
    truncated: false,
  }
  assert_eq(
    keep_response(summary, after, 5, introduced=1),
    "\{summary}\nmoon check: applied with 8 error(s) kept (only 1 newly introduced ≤ revert_when_errors_above=5; the rest pre-existed), 0 warning(s)\na.mbt:1:1-1:2: boom",
  )
}

///|
test "revert_report names the introduced count and the first errors" {
  let after : @auto_check.CheckErrors = {
    error_count: 9,
    warning_count: 3,
    first_errors: ["a.mbt:1:1-1:2: boom", "b.mbt:2:1-2:2: bang"],
    truncated: false,
  }
  let report = revert_report(
    [sample_write("a.mbt", 4), sample_write("b.mbt", 2)],
    after,
    introduced=9,
    threshold=5,
    restore_failures=[],
  )
  assert_eq(
    report,
    (
      #|reverted: applied 6 edit(s) across 2 file(s), but moon check then reported 9 error(s) (9 newly introduced > revert_when_errors_above=5); all 2 file(s) were rolled back to their pre-batch contents.
      #|first 2 error(s):
      #|a.mbt:1:1-1:2: boom
      #|b.mbt:2:1-2:2: bang
      #|re-issue with more precise old_strings (include the receiver) and/or smaller batches so a replacement cannot stray onto unintended sites.
    ),
  )
}

///|
test "revert_report marks a truncated count and a failed restore" {
  let after : @auto_check.CheckErrors = {
    error_count: 400,
    warning_count: 0,
    first_errors: ["a.mbt:1:1-1:2: boom"],
    truncated: true,
  }
  let report = revert_report(
    [sample_write("a.mbt", 1)],
    after,
    introduced=400,
    threshold=5,
    restore_failures=["a.mbt"],
  )
  assert_true(report.contains("reported ≥400 error(s)"))
  assert_true(report.contains("WARNING: could not restore 1 file(s): a.mbt"))
}

///|
test "batch_reject_report caps detailed files and labels lower bounds" {
  let rejections : Array[FileRejection] = [
    for index in 0..<5 => {
      (
        {
          path: "lib/f\{index}.mbt",
          introduced: 1,
          truncated: index == 0,
          section: "lib/f\{index}.mbt: would gain 1 new parse error(s):\nlib/f\{index}.mbt:1:1: e",
        } : FileRejection)
    }
  ]
  let report = batch_reject_report(rejections, total=5, any_truncated=true)
  assert_true(
    report.contains(
      "rejected: the batch would introduce at least 5 new parse error(s) across 5 file(s), so NO files were changed.",
    ),
  )
  // Only the first RejectedFileDisplayLimit files are detailed; the rest are
  // named in the overflow line.
  assert_true(report.contains("lib/f2.mbt: would gain"))
  assert_false(report.contains("lib/f3.mbt: would gain"))
  assert_true(report.contains("…and 2 more file(s): lib/f3.mbt, lib/f4.mbt"))
  assert_true(report.contains("revert_on_parse_errors=false"))
}
