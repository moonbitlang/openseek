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
  file_state? : @agent_tool.FileStateMap = FileStateMap(),
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    program_callable=true,
    name="multi_edit",
    description=(
      #|Apply many exact line-anchored replacements across one or more files in a single
      #|validated batch — the efficient path for compiler-feedback repair: when `moon
      #|check` (or another analyzer) reports several known locations, fix them all in one
      #|call instead of many separate `edit` calls. Supply the edits two ways and either
      #|or both are used (they are concatenated): `edits` is an inline array of edit
      #|objects; `edits_file` is the path to a JSON file holding an array of the same
      #|objects — for large batches, generate that file from compiler diagnostics with a
      #|script and pass its path. Each edit is {file, old_string, new_string, start_line,
      #|optional end_line}: `file` is the path to change; `start_line` (1-based) anchors
      #|the search and `end_line` bounds it, so old_string can be the small exact span
      #|instead of a large context block; each edit replaces the first matching span in
      #|its range. Matching normalizes CRLF (`\r\n`) to LF and curly/smart quotes to
      #|straight quotes, so old_string with LF matches `\r\n` in the file and straight
      #|quotes match curly quotes. Make old_string uniquely identify the flagged code — include the
      #|receiver, e.g. `args.length()` — so a rename cannot stray onto a same-named call
      #|elsewhere on the line. List all edits for a given file contiguously. To INSERT
      #|instead of replace, set old_string to the empty string: new_string is inserted at
      #|the start of start_line (any start_line past the last line appends at end of file
      #|— e.g. 999999; in MoonBit top-level order does not matter, so append new functions
      #|and tests at end of file rather than inserting mid-file). Combine changes on the
      #|same line (or one tight span) into a single edit, because adjacent or overlapping
      #|edits collide and the whole batch is rejected. Every edit is validated against the
      #|original files before anything is written; a batch that would introduce lex/parse
      #|errors into a .mbt file is also rejected BEFORE writing (see
      #|revert_on_parse_errors); if any edit fails, no files are changed.
    ),
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
          "description": (
            #|Path to a JSON file holding an array of the same edit objects — a response
            #|file for large, script-generated batches. Concatenated with inline edits
            #|when both are given.
          ),
          "examples": ["fixes.json"],
        },
        "revert_if_error_delta_greater_or_equal": {
          "type": "integer",
          "description": (
            #|Auto-revert safety net, default 10 (edit defaults off). Revert
            #|the entire batch when the reported error count change (after - before)
            #|is >= this non-negative threshold. 0 requires a decrease; 1 permits an
            #|unchanged total. Counts are not proof that no new problems exist. Caveat:
            #|moon check skips the dependents of a failing package, so in a tree that
            #|already has errors a batch that FIXES them lets the build reach further
            #|and report errors that were always there; new errors can also hide unchecked
            #|packages and lower the count. The revert report's `comparability:` line classifies the new
            #|errors with moon's package graph: inside an edited file (over-match), in
            #|code that compiled cleanly before and depends on the edit (breakage), in
            #|packages independent of the edit (certified reach — it names the exact
            #|value to re-issue the unchanged batch with), or in dependents of a package
            #|the batch fixed (plausible reach — it names the sites to vet first, then
            #|the value). Review those diagnostics before raising the threshold: to admit
            #|a delta D, the threshold must be at least D + 1.
          ),
          "examples": [10],
        },
        "revert_on_parse_errors": {
          "type": "boolean",
          "description": (
            #|Syntax gate, on by default. Before the batch is written, each edited
            #|syntax-checkable file's (.mbt, .mbt.md, moon.mod, moon.pkg) rendered result
            #|is parsed standalone (moonc syncheck); if any file would gain new lex/parse
            #|errors — measured against its pre-batch content parsed the same way, so
            #|pre-existing parse errors are ignored — the WHOLE batch is rejected with no
            #|files changed, and the call returns the errors with excerpts of the would-be
            #|content. Type errors never trigger this gate (the post-write
            #|revert_if_error_delta_greater_or_equal guard covers those); in .mbt.md only the checked
            #|(`mbt check` / `moonbit check`) fenced blocks are parsed. Set false only to
            #|intentionally produce content that does not parse (e.g. a fixture).
          ),
          "examples": [false],
        },
        "revert_if_warning_delta_greater_or_equal": {
          "type": "integer",
          "description": (
            #|Post-write warning guard, off unless given. moon check runs before the batch
            #|is written (the baseline) and after it; revert when the reported warning
            #|count change (after - before) is >= this non-negative threshold.
            #|0 requires a decrease; 1 allows an unchanged total. The same rule as edit.
            #|Errors can change which packages are checked, so a lower count does not
            #|prove no new problems. Review diagnostics before raising the threshold
            #|above the observed delta to accept a justified change.
            #|Shares the error guard's checks; the result's data carries introduced_count and
            #|removed_count per severity. If the tree cannot be checked, a warning-guarded
            #|batch is not written. For a warning-fix loop that needs to know WHICH fix
            #|misfired, prefer one guarded `edit` per diagnostic.
          ),
          "examples": [0],
        },
      },
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
  let args = @decode.decode_args(arguments) catch {
    error =>
      return @agent_tool.respond(
        "error: multi_edit requires \{@tool_error.failure_message("\{error}")}",
        is_error=true,
        data={ "outcome": "error" },
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
    return @agent_tool.respond(
      "error: multi_edit requires edits and/or edits_file (no edits were provided)",
      is_error=true,
      data={ "outcome": "error" },
    )
  }
  multi_edit_files(
    workspace_root,
    edits,
    args.revert_if_error_delta_greater_or_equal,
    revert_on_parse_errors=args.revert_on_parse_errors,
    revert_if_warning_delta_greater_or_equal=args.revert_if_warning_delta_greater_or_equal,
    file_state~,
    write_scope?,
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
  fn failed(message : String) -> @agent_tool.ToolAction {
    @agent_tool.respond(message, is_error=true, brief="multi_edit", data={
      "outcome": "error",
    })
  }

  let path = @workspace_path.resolve(workspace_root, spec)
  let text = @fs.read_file(path).text() catch {
    error =>
      return Err(
        failed("error: multi_edit could not read edits file \{path}: \{error}"),
      )
  }
  let json = @json.parse(text) catch {
    error =>
      return Err(
        failed(
          "error: multi_edit edits file \{path} is not valid JSON: \{error}",
        ),
      )
  }
  let edits = @decode.decode_edits_json(json) catch {
    error =>
      return Err(
        failed(
          "error: multi_edit requires \{@tool_error.failure_message("\{error}")} in edits file \{path}",
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
/// Batch pipeline — validate everything, gate, then write; failures before the
/// first write always mean "no changes applied":
///
///   resolve paths ── group contiguous edits per resolved file
///   validate every group ── load ── anchor-check each edit ── plan the write
///     └─ ANY failure ── aggregate all failures ── report; nothing written
///   parse gate ── would-be content worse than the original? ── reject batch
///   apply writes in file order
///     └─ IO fault mid-batch ── report with "earlier files may be written"
///   auto check (source files) ── error/warning count delta reaches its threshold?
///     └─ revert every written file ── report per-file revert status
async fn multi_edit_files(
  workspace_root : String,
  edits : Array[@decode.MultiEditItem],
  revert_if_error_delta_greater_or_equal : Int?,
  revert_on_parse_errors~ : Bool,
  revert_if_warning_delta_greater_or_equal~ : Int?,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
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
    return @agent_tool.respond(message, is_error=true, brief~, data={
      "outcome": "error",
    })
  }
  let groups = group_contiguous(resolved)
  let failures : Array[EditFailure] = []
  let prepared : Array[PreparedFile] = []
  for group in groups {
    let content = @fs.read_file(group.path).text() catch {
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
    prepared.push({ file: group.file, path: group.path, content, plans, })
  }
  if failures.length() > 0 {
    return @agent_tool.respond(
      failure_report(failures),
      is_error=true,
      brief~,
      data=failures_data(failures),
    )
  }
  // Render each file and run the write guard before touching disk, so a guarded
  // path aborts the whole batch instead of leaving earlier files written. The
  // containment gate (confined worker registries) joins the same all-or-nothing
  // contract: one out-of-scope path rejects the batch with nothing written.
  let writes : Array[PreparedWrite] = []
  for prepared_file in prepared {
    let new_content = apply_plans(prepared_file.content, prepared_file.plans)
    let guard_message = match
      @manifest_error.write_error(prepared_file.path, new_content) {
      Some(message) => Some(message)
      None =>
        if write_scope is Some(scope) {
          scope
          .deny_reason(prepared_file.path)
          .map(reason => "write blocked: \{reason}")
        } else {
          None
        }
    }
    match guard_message {
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
    return @agent_tool.respond(
      failure_report(failures),
      is_error=true,
      brief~,
      data=failures_data(failures),
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
  // Measure every touched project before writing, using the same scope for
  // both guards. An unavailable baseline refuses the batch without a write.
  let check_paths = batch_projects(writes)
  let baseline = if !check_paths.is_empty() {
    fn not_verified(reason : String) -> @agent_tool.ToolAction {
      @agent_tool.respond(
        "not applied: a diagnostic guard is active, but moon check could not verify the tree (\{reason}); no files were changed",
        is_error=true,
        brief~,
        data=batch_data("unverified", writes, { "reason": reason.to_json() }),
      )
    }

    match measure_baseline(check_paths) {
      Measured(baseline) => {
        for write in writes {
          let current = @fs.read_file(write.path).text() catch {
            error =>
              return not_verified("could not re-read \{write.path}: \{error}")
          }
          if current != write.original_content {
            return not_verified(
              "\{write.path} changed during the baseline check; re-read and retry",
            )
          }
        }
        Some(baseline)
      }
      Nothing => None
      Refused(reason) => return not_verified(reason)
    }
  } else {
    None
  }
  // A checked batch interrupted while being written or checked must
  // not stay on disk unverified: put every original back before the
  // cancellation unwinds. Registered before the first write.
  async fn restore_on_unwind() -> Unit {
    if baseline is Some(_) {
      @async.protect_from_cancel(() => {
        restore_files(writes, write_scope?) |> ignore
      })
    }
  }

  errdefer restore_on_unwind()
  // A checked batch that fails mid-write restores the files touched so far.
  let written : Array[PreparedWrite] = []
  async fn write_failed(problem : String) -> @agent_tool.ToolAction {
    if baseline is Some(_) {
      let restore_failures = @async.protect_from_cancel(() => {
        restore_files(written, write_scope?)
      })
      return @agent_tool.respond(
        "error multi_editing \{problem}; the \{written.length()} file(s) touched so far were restored (diagnostic guard)\{restore_note(restore_failures)}",
        is_error=true,
        brief~,
        // Only a complete restore is a rollback: with a file the restore
        // could not put back, the tree is partially modified and says so.
        data=batch_data("error", writes, {
          "partial": (!restore_failures.is_empty()).to_json(),
          "rolled_back": restore_failures.is_empty().to_json(),
          "restore_failures": string_array(restore_failures),
        }),
      )
    }
    @agent_tool.respond(
      "error multi_editing \{problem}; earlier files in the batch may already be written",
      is_error=true,
      brief~,
      data=batch_data("error", writes, { "partial": true }),
    )
  }

  for write in writes {
    // Containment re-check at the moment of writing: the batch gate above
    // decided on filesystem state that awaits ago may have changed.
    if write_scope is Some(scope) &&
      scope.deny_reason(write.path) is Some(reason) {
      return write_failed("\{write.path}: write blocked: \{reason}")
    }
    // Counted as touched before the attempt: the write truncates before it
    // writes, so a failure can leave the file empty, and the rollback must
    // cover it.
    written.push(write)
    @fs.write_file(write.path, write.new_content, create_mode=CreateOrTruncate) catch {
      error =>
        return write_failed("\{write.path}: error writing file: \{error}")
    }
  }
  // Compare the checked projects again and roll back the batch if either
  // count delta reaches its threshold. Non-project files have no check.
  let response = if check_paths.is_empty() {
    // No file in a MoonBit project: nothing to check, the batch stands.
    @agent_tool.respond(
      success_summary(writes),
      brief=success_brief(writes),
      data=batch_data("applied", writes, Map([])),
    )
  } else {
    revert_guarded_response(
      check_paths,
      writes,
      revert_if_error_delta_greater_or_equal.unwrap_or(10),
      baseline,
      warnings_guard=revert_if_warning_delta_greater_or_equal,
      write_scope?,
    )
  }
  // Record each file's provenance and content digest AFTER the auto-revert guard
  // above, which may have rewritten some files back to their pre-batch content —
  // so read each file's FINAL content rather than assuming the new content stuck.
  // A targeted edit's continuity turns on the PRE-batch content (original_content
  // = what the tool read): a `Created` file keeps that provenance only if the tool
  // saw the agent's own content, so a file rebound before the batch is downgraded
  // and not deletable. (A write that fails mid-batch returns earlier, before this
  // loop, leaving the already-written files unrecorded — a safe under-record for
  // that error case.)
  for write in writes {
    let seen_digest = @agent_tool.content_digest(write.original_content)
    let new_digest = @agent_tool.content_digest(write.new_content)
    let final_content = @fs.read_file(write.path).text() catch {
      _ => write.new_content
    }
    let final_digest = @agent_tool.content_digest(final_content)
    // Only record when the file's final content is one the tool itself left: the
    // applied `new_content` (kept), or the `original_content` (rolled back by the
    // revert guard). If it is neither, an external writer changed the file during
    // the guard's `moon check` window — leave any prior entry untouched (its
    // recorded digest will not match the replacement, so `remove` refuses) rather
    // than bless the external content as the agent's.
    if final_digest == new_digest || final_digest == seen_digest {
      file_state.record_edited(write.path, seen_digest, final_digest)
    }
  }
  response
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
  errors : Array[@auto_check.ParseGateError]
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
    let target = @fs.realpath(write.path) catch { _ => write.path }
    // Gate under every syncheck kind this file could be classified as. A
    // regular file yields one kind; a symlink that crosses kinds (e.g.
    // `link.mbt -> doc.mbt.md`) yields two, and moon's classification of such a
    // link is ambiguous, so check both and reject on the first that regresses.
    // See `gate_paths`.
    for gate_path in @auto_check.gate_paths(write.path, target) {
      let gate = @auto_check.content_parse_errors(gate_path, write.new_content) catch {
        _ => None
      }
      guard gate is Some(gate) && gate.errors.length() > 0 else { continue }
      let before = @auto_check.content_parse_errors(
        gate_path,
        write.original_content,
      ) catch {
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
        errors: gate.errors,
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
    @agent_tool.respond(
      batch_reject_report(rejections, total~, any_truncated~),
      is_error=true,
      brief="multi_edit rejected (\{bound}\{total} parse error(s))",
      data=batch_data("rejected", writes, {
        "introduced": total.to_json(),
        "parse_errors": Json::array(
          [
            for rejection in rejections => {
              {
                "path": rejection.path.to_json(),
                "introduced": rejection.introduced.to_json(),
                "errors": Json::array(
                  [
                    for
                      error in rejection.errors[:rejection.errors
                      .length()
                      .min(IntroducedDisplayLimit)] => {
                      {
                        "loc": error.loc.to_json(),
                        "message": error.message.to_json(),
                      }
                    }
                  ],
                ),
              }
            }
          ],
        ),
      }),
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
/// Both guards compare reported count changes over the same checked projects.
async fn revert_guarded_response(
  check_paths : Array[String],
  writes : Array[PreparedWrite],
  threshold : Int,
  baseline : Baseline?,
  warnings_guard~ : Int?,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  guard baseline is Some(before) else {
    return reverted_unverified(writes, "no pre-write baseline", write_scope?)
  }
  let measured = match measure_baseline(check_paths) {
    Measured(value) => value
    Refused(reason) => return reverted_unverified(writes, reason, write_scope?)
    Nothing =>
      return reverted_unverified(
        writes,
        "the checked project is no longer available",
        write_scope?,
      )
  }
  if measured.plan_failure is Some(reason) {
    return reverted_unverified(
      writes,
      "the build plan fails after the batch (\{reason}); repair the build plan first, before any other edit",
      write_scope?,
    )
  }
  // No plan before the batch and one now: an improvement whatever the counts
  // say, with no baseline to compare them against, so the batch is kept and
  // the check simply reported.
  if before.plan_failure is Some(reason) {
    return @agent_tool.respond(
      "\{success_summary(writes)}\nmoon check: the build plan is computable again (before this batch: \{reason}); \{error_count_label(measured.all)} error(s), \{measured.all.warning_count} warning(s) — the guards had no baseline to compare against",
      brief=success_brief(writes),
      data=batch_data("applied", writes, {
        "check": measured.first.to_json(),
        "plan_repaired": true,
      }),
    )
  }
  let after = measured.all
  let error_delta = after.error_count - before.all.error_count
  let delta = @auto_check.introduced(before.all, after)
  let removed = @auto_check.introduced(after, before.all)
  let counts = delta_json(delta, removed)
  if error_delta >= threshold {
    let collected = @diagnostic_guard.gather_comparability(
      check_paths[0],
      Some(before.all),
      after,
      writes.map(write => write.path),
    )
    // A single package graph cannot certify attribution across modules.
    let evidence = if check_paths.length() > 1 {
      { ..collected, graph_available: false, }
    } else {
      collected
    }
    let restore_failures = restore_files(writes, write_scope?)
    return reverted_by_errors(
      writes,
      after,
      introduced=error_delta,
      threshold~,
      restore_failures~,
      evidence~,
      counts~,
    )
  }
  if warnings_guard is Some(limit) &&
    after.warning_count - before.all.warning_count >= limit {
    let restore_failures = restore_files(writes, write_scope?)
    return reverted_by_warnings(
      writes,
      before,
      measured.first,
      after,
      delta,
      removed,
      limit~,
      restore_failures~,
    )
  }
  let extra : Map[String, Json] = {
    "check": measured.first.to_json(),
    "threshold": threshold.to_json(),
    "error_delta": error_delta.to_json(),
    "baseline": baseline_json(before.first),
  }
  for key, value in counts {
    extra[key] = value
  }
  if check_paths.length() > 1 {
    extra["check_all"] = after.to_json()
    extra["baseline_all"] = baseline_json(before.all)
  }
  let caveat = if before.all.error_count > 0 {
    "\nnote: errors can change which packages moon check reaches; a lower count does not prove no new problems."
  } else {
    ""
  }
  @agent_tool.respond(
    keep_response(success_summary(writes), after, threshold, error_delta~) +
    (if check_paths.length() > 1 {
      "\nall \{check_paths.length()} project(s): \{after.error_count} error(s), \{after.warning_count} warning(s)"
    } else {
      ""
    }) +
    caveat,
    brief=success_brief(writes),
    data=batch_data("applied", writes, extra),
  )
}

///|
/// One representative path per distinct project the batch touches, in batch
/// order: each written path and, for a link, its resolved target, keyed by
/// the canonical project directory so `/tmp/x` and `/private/tmp/x` are one.
/// Paths outside any MoonBit project are dropped.
async fn batch_projects(writes : Array[PreparedWrite]) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let representatives : Array[String] = []
  async fn consider(path : String) -> Unit {
    guard @auto_check.check_cwd(path) is Some(dir) else { return }
    let key = @fs.realpath(dir) catch { _ => dir }
    if !seen.contains(key) {
      seen[key] = true
      representatives.push(path)
    }
  }

  for write in writes {
    consider(write.path)
    let target = @fs.realpath(write.path) catch { _ => write.path }
    if target != write.path {
      consider(target)
    }
  }
  representatives
}

///|
/// Both guards compare the merged tally; the first-project view is retained
/// for existing structured result consumers.
priv struct Baseline {
  first : @auto_check.CheckErrors
  all : @auto_check.CheckErrors
  // Set when moon could not compute a build plan for a checked project (with
  // its explanation); the tallies are then moon's empty ones. A tree with no
  // plan is the floor: a batch that makes the plan computable again is kept
  // as an improvement, and one that leaves it broken is rolled back.
  plan_failure : String?
}

///|
priv enum BaselineOutcome {
  Measured(Baseline)
  // A check that could not run, or overflowed: a partial view is no verdict.
  Refused(String)
  // No project to check.
  Nothing
}

///|
/// moon names a diagnostic's file relative to the project it checked (or
/// absolutely), so two projects can each report a `lib/lib.mbt`. Before two
/// tallies are merged, each relative path is prefixed with its project's
/// directory, so a warning that moves between projects is not the same
/// identity in both. The first project's raw tally is retained for existing
/// result consumers; both guards compare the merged counts.
async fn qualified(
  path : String,
  tally : @auto_check.CheckErrors,
) -> @auto_check.CheckErrors {
  guard @auto_check.check_cwd(path) is Some(project) else { return tally }
  fn place(site : @auto_check.ErrorSite) -> @auto_check.ErrorSite {
    match site.path {
      Some(file) if !file.has_prefix("/") &&
        !file.has_prefix("\\") &&
        !(file.length() > 1 && file[1:2] == ":") =>
        { ..site, path: Some("\{project}/\{file}"), }
      _ => site
    }
  }

  {
    ..tally,
    errors: tally.errors.map(place),
    warnings: tally.warnings.map(place),
  }
}

///|
async fn measure_baseline(paths : Array[String]) -> BaselineOutcome {
  let mut first : @auto_check.CheckErrors? = None
  let mut all : @auto_check.CheckErrors? = None
  let mut plan_failure : String? = None
  for path in paths {
    let tally = match @auto_check.check(path) {
      Checked(tally) if tally.truncated => return Refused(TruncatedCapture)
      Checked(tally) => tally
      Failed(code, tally, detail) => {
        plan_failure = Some(
          "moon check exited \{code} without diagnostics: \{detail}",
        )
        tally
      }
      NotApplicable =>
        return Refused("a checked project is no longer available")
      Unavailable(reason) => return Refused(reason)
    }
    if first is None {
      first = Some(tally)
    }
    let placed = qualified(path, tally)
    all = Some(all.map_or(placed, sum => sum.merged(placed)))
  }
  match (first, all) {
    (Some(first), Some(all)) => Measured({ first, all, plan_failure, })
    _ => Nothing
  }
}

///|
/// Why a guard cannot compare an overflowed capture: the lists are then
/// windows onto moon's output, and a site can enter one without being new.
const TruncatedCapture : String = "moon check hid some diagnostic sites behind its diagnostic limit, so the guard cannot compare the two runs"

///|
/// How many introduced sites a warning revert lists, in text and data.
const IntroducedDisplayLimit : Int = 20

///|
/// The batch is on disk but its post-batch check could not be trusted: roll
/// everything back and say why.
async fn reverted_unverified(
  writes : Array[PreparedWrite],
  reason : String,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  let restore_failures = restore_files(writes, write_scope?)
  @agent_tool.respond(
    "reverted: \{reason} (diagnostic guard), so all \{writes.length()} file(s) were rolled back to their pre-batch contents.\{restore_note(restore_failures)}",
    is_error=true,
    brief="multi_edit reverted (unverified)",
    data=batch_data("reverted", writes, {
      "reason": "unverified",
      "restore_failures": string_array(restore_failures),
    }),
  )
}

///|
/// The error guard fired: the existing revert report, plus the evidence as
/// data so a script can branch on the verdict without parsing prose.
fn reverted_by_errors(
  writes : Array[PreparedWrite],
  after : @auto_check.CheckErrors,
  introduced~ : Int,
  threshold~ : Int,
  restore_failures~ : Array[String],
  evidence~ : @diagnostic_guard.Comparability,
  counts~ : Map[String, Json],
) -> @agent_tool.ToolAction {
  let extra : Map[String, Json] = {
    "reason": "error_delta",
    "check": after.to_json(),
    "introduced_errors": introduced.to_json(),
    "threshold": threshold.to_json(),
    "restore_failures": string_array(restore_failures),
  }
  for key, value in counts {
    extra[key] = value
  }
  for key, value in evidence.feedback(delta=introduced) {
    extra[key] = value
  }
  @agent_tool.respond(
    revert_report(
      writes,
      after,
      introduced~,
      threshold~,
      restore_failures~,
      evidence~,
    ),
    is_error=true,
    brief="multi_edit reverted (\{introduced} new error(s))",
    data=batch_data("reverted", writes, extra),
  )
}

///|
/// The warning guard fired: the batch is rolled back and the introduced
/// warnings are listed, with the reach caveat when the baseline had errors.
fn reverted_by_warnings(
  writes : Array[PreparedWrite],
  baseline : Baseline,
  after_first : @auto_check.CheckErrors,
  after : @auto_check.CheckErrors,
  delta : @auto_check.Introduced,
  removed : @auto_check.Introduced,
  limit~ : Int,
  restore_failures~ : Array[String],
) -> @agent_tool.ToolAction {
  let before = baseline.all
  let count = delta.warnings.length()
  let shown = delta.warnings[:count.min(IntroducedDisplayLimit)]
  let warning_delta = after.warning_count - before.warning_count
  let head = "reverted: applied \{total_edit_count(writes)} edit(s) across \{writes.length()} file(s), but the warning count changed by \{warning_delta} (>= revert_if_warning_delta_greater_or_equal=\{limit}); all \{writes.length()} file(s) were rolled back to their pre-batch contents."
  let listed = "\nintroduced:\n" +
    [ for site in shown => site.line() ].join("\n")
  let more = if count > shown.length() {
    "\n… \{count - shown.length()} more"
  } else {
    ""
  }
  let reach_caveat = before.error_count > 0
  let caveat = if reach_caveat {
    "\nnote: the baseline already had \{before.error_count} error(s); moon skips the dependents of a failing package, so a batch that lets the build reach further can surface warnings that were always there."
  } else {
    ""
  }
  let counts = delta_json(delta, removed)
  @agent_tool.respond(
    "\{head}\{listed}\{more}\{caveat}\{restore_note(restore_failures)}",
    is_error=true,
    brief="multi_edit reverted (warning delta \{warning_delta})",
    data=batch_data("reverted", writes, {
      "reason": "warning_delta",
      "check": after_first.to_json(),
      "check_all": after.to_json(),
      "baseline": baseline_json(baseline.first),
      "baseline_all": baseline_json(before),
      "introduced_count": counts["introduced_count"],
      "removed_count": counts["removed_count"],
      "reach_caveat": reach_caveat.to_json(),
      "introduced": {
        "errors": [],
        "warnings": Json::array([ for site in shown => site.to_json() ]),
        "complete": true,
      },
      "restore_failures": string_array(restore_failures),
    }),
  )
}

///|
/// The delta a guard measured, quantified for `data`: how many diagnostics of
/// each severity the batch introduced and how many it removed.
fn delta_json(
  introduced : @auto_check.Introduced,
  removed : @auto_check.Introduced,
) -> Map[String, Json] {
  {
    "introduced_count": {
      "errors": introduced.errors.length().to_json(),
      "warnings": introduced.warnings.length().to_json(),
    },
    "removed_count": {
      "errors": removed.errors.length().to_json(),
      "warnings": removed.warnings.length().to_json(),
    },
  }
}

///|
fn restore_note(restore_failures : Array[String]) -> String {
  if restore_failures.is_empty() {
    ""
  } else {
    "\nWARNING: could not restore \{restore_failures.length()} file(s): \{restore_failures.join(", ")} — inspect them manually."
  }
}

///|
/// The result's machine-readable `data`: the outcome, the files the batch
/// covers with their edit counts, and whatever the outcome adds.
fn batch_data(
  outcome : String,
  writes : Array[PreparedWrite],
  extra : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = {
    "outcome": outcome.to_json(),
    "files": Json::array(
      [
        for write in writes => {
          { "path": write.path.to_json(), "edits": write.edit_count.to_json() }
        }
      ],
    ),
    "edit_count": total_edit_count(writes).to_json(),
  }
  for key, value in extra {
    fields[key] = value
  }
  Json::object(fields)
}

///|
/// Pre-write validation failed: nothing was written, and each problem names
/// the file, the edit index (absent for a file-level problem), and the range.
fn failures_data(failures : Array[EditFailure]) -> Json {
  {
    "outcome": "failed",
    "failures": Json::array(
      [
        for failure in failures => {
          let fields : Map[String, Json] = { "file": failure.file.to_json() }
          if failure.index is Some(index) {
            fields["index"] = index.to_json()
          }
          // A file-level problem (unreadable, write-guarded) has no range.
          if failure.range != "" {
            fields["range"] = failure.range.to_json()
          }
          fields["message"] = failure.message.to_json()
          Json::object(fields)
        }
      ],
    ),
  }
}

///|
fn string_array(items : Array[String]) -> Json {
  Json::array([ for item in items => item.to_json() ])
}

///|
fn baseline_json(before : @auto_check.CheckErrors) -> Json {
  {
    "error_count": before.error_count.to_json(),
    "warning_count": before.warning_count.to_json(),
  }
}

///|
/// Write `write.original_content` to every file, returning the paths that could not be
/// written (best effort — a restore must not raise mid-rollback). A
/// non-empty result is surfaced in the revert report so a half-restored tree is
/// never reported as a clean rollback. The containment scope gates these
/// restore writes too — a path whose resolution changed since the
/// batch was admitted is skipped and reported rather than written blind.
async fn restore_files(
  writes : Array[PreparedWrite],
  write_scope? : @write_scope.WriteScope,
) -> Array[String] {
  let failures : Array[String] = []
  for write in writes {
    if write_scope is Some(scope) && scope.deny_reason(write.path) is Some(_) {
      failures.push(write.path)
      continue
    }
    @fs.write_file(
      write.path,
      write.original_content,
      create_mode=CreateOrTruncate,
    ) catch {
      _ => failures.push(write.path)
    }
  }
  failures
}

///|
/// The kept-batch response: the success summary plus an honest `moon check`
/// status line showing both the remaining errors and the measured count delta.
fn keep_response(
  summary : String,
  after : @auto_check.CheckErrors,
  threshold : Int,
  error_delta~ : Int,
) -> String {
  if after.error_count == 0 {
    return "\{summary}\nmoon check: ok — 0 errors, \{after.warning_count} warning(s)"
  }
  let errors = error_count_label(after)
  let header = "\{summary}\nmoon check: applied with \{errors} error(s) kept (error count change \{error_delta} < revert_if_error_delta_greater_or_equal=\{threshold}), \{after.warning_count} warning(s)"
  let first_errors = after.first_errors()
  if first_errors.is_empty() {
    header
  } else {
    "\{header}\n\{first_errors.join("\n")}"
  }
}

///|
/// The reverted-batch report: what was applied, how many new errors triggered
/// the rollback, the first few of them, the comparability verdict with its
/// evidence, and how to proceed.
fn revert_report(
  writes : Array[PreparedWrite],
  after : @auto_check.CheckErrors,
  introduced~ : Int,
  threshold~ : Int,
  restore_failures~ : Array[String],
  evidence~ : @diagnostic_guard.Comparability,
) -> String {
  let total = total_edit_count(writes)
  let head = "reverted: applied \{total} edit(s) across \{writes.length()} file(s), but moon check then reported \{error_count_label(after)} error(s) (\{introduced} error count change >= revert_if_error_delta_greater_or_equal=\{threshold}); all \{writes.length()} file(s) were rolled back to their pre-batch contents."
  let first_errors = after.first_errors()
  let errors = if first_errors.is_empty() {
    ""
  } else {
    "\nfirst \{first_errors.length()} error(s):\n\{first_errors.join("\n")}"
  }
  "\{head}\{errors}\{restore_note(restore_failures)}\n\{@diagnostic_guard.comparability_advice(evidence, introduced~)}"
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
  let ended : Set[String] = Set([])
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
        ended.add(path)
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
    if groups is [.., last] && last.path == edit.path {
      last.items.push(edit)
    } else {
      groups.push({ file: edit.file, path: edit.path, items: [edit], })
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
  if writes is [only] {
    "multi_edit \{@agent_tool.brief_basename(only.path)} (\{total}×)"
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
    let at = @line_offset.line_start_offset(content, item.start_line).clamp(
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
  let (norm_content, offset_map) = @matching.normalize_content_for_matching(
    content,
  )
  let (norm_old, _) = @matching.normalize_content_for_matching(item.old_string)
  let region = select_edit_region(norm_content, item.start_line, item.end_line)
  let match_offset = match region.body.find(norm_old) {
    Some(offset) => Some(offset)
    None => @matching.find_quote_normalized_match(region.body, norm_old)
  }
  guard match_offset is Some(offset) else {
    return Invalid({
      file,
      index: Some(index),
      range,
      message: "old_string not found",
    })
  }
  let norm_global = region.start_offset + offset
  let orig_start = offset_map[norm_global]
  let orig_end = if norm_global + norm_old.length() < offset_map.length() {
    offset_map[norm_global + norm_old.length()]
  } else {
    content.length()
  }
  Valid({
    index,
    start: orig_start,
    end: orig_end,
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
  ordered.fold(init=content, (output, plan) => {
    "\{output.unsafe_substring(start=0, end=plan.start)}\{plan.new_string}\{output.unsafe_substring(start=plan.end, end=output.length())}"
  })
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
  let start = @line_offset.line_start_offset(content, start_line)
  let end = match end_line {
    Some(line) => @line_offset.line_end_offset(content, line)
    None => content.length()
  }
  let start = start.clamp(min=0, max=content.length())
  let end = end.clamp(min=start, max=content.length())
  { body: content.unsafe_substring(start~, end~), start_offset: start, }
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
test "batch_reject_report caps detailed files and labels lower bounds" {
  let rejections : Array[FileRejection] = [
    for index in 0..<5 => {
      (
        {
          path: "lib/f\{index}.mbt",
          introduced: 1,
          truncated: index == 0,
          section: "lib/f\{index}.mbt: would gain 1 new parse error(s):\nlib/f\{index}.mbt:1:1: e",
          errors: [],
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
