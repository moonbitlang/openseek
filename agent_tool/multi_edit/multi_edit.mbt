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
        "revert_when_errors_above": {
          "type": "integer",
          "description": (
            #|Auto-revert safety net. After the batch is written, `moon check` runs; if
            #|this batch INTRODUCES more than this many new compile errors (measured
            #|against the pre-batch error count, so pre-existing errors and all warnings
            #|are ignored), the entire batch is rolled back to its pre-batch contents and
            #|the call returns an error listing the first few new errors — so an
            #|over-matching replace cannot leave a broken tree to untangle. Default 10;
            #|the host clamps the effective value to 0..200 (0 reverts on any new error).
            #|A batch that keeps or reduces the error count is never reverted. Caveat:
            #|moon check skips the dependents of a failing package, so in a tree that
            #|already has errors a batch that FIXES them lets the build reach further
            #|and report errors that were always there — the count rises without
            #|breakage. The revert report's `comparability:` line classifies the new
            #|errors with moon's package graph: inside an edited file (over-match), in
            #|code that compiled cleanly before and depends on the edit (breakage), in
            #|packages independent of the edit (certified reach — it names the exact
            #|value to re-issue the unchanged batch with), or in dependents of a package
            #|the batch fixed (plausible reach — it names the sites to vet first, then
            #|the value). Raise this only to the value that line names.
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
            #|revert_when_errors_above guard covers those); in .mbt.md only the checked
            #|(`mbt check` / `moonbit check`) fenced blocks are parsed. Set false only to
            #|intentionally produce content that does not parse (e.g. a fixture).
          ),
          "examples": [false],
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
    )
  }
  multi_edit_files(
    workspace_root,
    edits,
    args.revert_when_errors_above,
    revert_on_parse_errors=args.revert_on_parse_errors,
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
  let brief = "multi_edit"
  let path = @workspace_path.resolve(workspace_root, spec)
  let text = @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      return Err(
        @agent_tool.respond(
          "error: multi_edit could not read edits file \{path}: \{error}",
          is_error=true,
          brief~,
        ),
      )
  }
  let json = @json.parse(text) catch {
    error =>
      return Err(
        @agent_tool.respond(
          "error: multi_edit edits file \{path} is not valid JSON: \{error}",
          is_error=true,
          brief~,
        ),
      )
  }
  let edits = @decode.decode_edits_json(json) catch {
    error =>
      return Err(
        @agent_tool.respond(
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
/// Batch pipeline — validate everything, gate, then write; failures before the
/// first write always mean "no changes applied":
///
///   resolve paths ── group contiguous edits per resolved file
///   validate every group ── load ── anchor-check each edit ── plan the write
///     └─ ANY failure ── aggregate all failures ── report; nothing written
///   parse gate ── would-be content worse than the original? ── reject batch
///   apply writes in file order
///     └─ IO fault mid-batch ── report with "earlier files may be written"
///   auto check (source files) ── errors above revert_when_errors_above?
///     └─ revert every written file ── report per-file revert status
async fn multi_edit_files(
  workspace_root : String,
  edits : Array[@decode.MultiEditItem],
  revert_when_errors_above : Int?,
  revert_on_parse_errors~ : Bool,
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
    return @agent_tool.respond(message, is_error=true, brief~)
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
    prepared.push({ file: group.file, path: group.path, content, plans, })
  }
  if failures.length() > 0 {
    return @agent_tool.respond(failure_report(failures), is_error=true, brief~)
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
    return @agent_tool.respond(failure_report(failures), is_error=true, brief~)
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
    // Containment re-check at the moment of writing: the batch gate above
    // decided on filesystem state that awaits ago may have changed.
    if write_scope is Some(scope) &&
      scope.deny_reason(write.path) is Some(reason) {
      return @agent_tool.respond(
        "error multi_editing \{write.path}: write blocked: \{reason}; earlier files in the batch may already be written",
        is_error=true,
        brief~,
      )
    }
    @fs.write_file(write.path, write.new_content, create_mode=CreateOrTruncate) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        return @agent_tool.respond(
          "error multi_editing \{write.path}: error writing file: \{error}; earlier files in the batch may already be written",
          is_error=true,
          brief~,
        )
    }
  }
  // The batch is on disk. Run the auto-revert guard from the first written
  // file's module: it appends `moon check` feedback and, if this batch
  // introduced too many new errors, rolls the whole batch back. A batch
  // spanning multiple modules only checks the first module's diagnostics, which
  // is acceptable for the in-project repair case. `writes` is non-empty here (a
  // non-empty batch with no failures always renders at least one write), but
  // match defensively rather than index blindly.
  let response = match writes {
    [first, ..] =>
      revert_guarded_response(
        first.path,
        writes,
        effective_revert_threshold(revert_when_errors_above),
        write_scope?,
      )
    [] =>
      @agent_tool.respond(success_summary(writes), brief=success_brief(writes))
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
      error if @async.is_being_cancelled() => raise error
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
    @agent_tool.respond(
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
const DefaultRevertThreshold : Int = 10

///|
/// The largest threshold the model may request. The model can make the guard
/// stricter (down to 0 — revert on any new error) and, when a revert report
/// shows the count delta to be a measurement artifact (see `Comparability`),
/// raise it to the reported delta so the same batch is admitted — but never
/// past this cap, so an overconfident call cannot silently disable the net.
const HostMaxRevertThreshold : Int = 200

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
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  let summary = success_summary(writes)
  let kept = @agent_tool.respond(summary, brief=success_brief(writes))
  let after = count_errors_or_none(check_path)
  // Not a MoonBit project, or the check could not run: keep the batch exactly
  // as applied, just as before this guardrail existed.
  guard after is Some(after) else { return kept }
  if after.error_count <= threshold {
    return @agent_tool.respond(
      keep_response(summary, after, threshold),
      brief=success_brief(writes),
    )
  }
  // Suspicious: the post-batch error count is over the line. Measure the
  // pre-batch baseline by restoring the originals and re-checking, so the guard
  // fires on errors this batch INTRODUCED, not on ones that were already there.
  let restore_failures = write_files(
    writes,
    write => write.original_content,
    write_scope?,
  )
  let before = count_errors_or_none(check_path)
  let before_count = before.map(b => b.error_count).unwrap_or(0)
  let introduced = after.error_count - before_count
  if introduced > threshold {
    // Over the line by count. Stay reverted (the originals are already back on
    // disk) — but the count alone cannot tell breakage from the build merely
    // reaching further, so the report carries the identity/location evidence
    // and, when it points at the latter, the value that admits this batch.
    let evidence = gather_comparability(check_path, before, after, writes)
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
    )
  } else {
    // False alarm: the errors were mostly pre-existing. Re-apply and keep —
    // but claim success only when every file actually made it back. A failed
    // restore skewed the baseline this decision used, and a failed re-apply
    // (IO fault, or a path whose resolution fell out of scope mid-flight)
    // leaves a mixed tree; both must reach the model, not vanish into a
    // success summary.
    let reapply_failures = write_files(
      writes,
      write => write.new_content,
      write_scope?,
    )
    if reapply_failures.length() > 0 {
      // Final contents are uncertain: these files may still hold their
      // pre-batch text.
      @agent_tool.respond(
        "error multi_editing: the batch was kept, but re-applying it did not fully succeed — these files may not hold the batch content: \{reapply_failures.join(", ")}; re-read them before further edits",
        is_error=true,
        brief="multi_edit partially re-applied",
      )
    } else if restore_failures.length() > 0 {
      // Every final write landed, so the tree holds the batch — but the
      // baseline this keep decision compared against was measured with these
      // files unrestored, so the decision itself deserves the caveat.
      @agent_tool.respond(
        keep_response(summary, after, threshold, introduced~) +
        "\nnote: the pre-batch baseline was measured with \{restore_failures.length()} file(s) unrestored (\{restore_failures.join(", ")}), so the introduced-error count may be understated",
        brief=success_brief(writes),
      )
    } else {
      @agent_tool.respond(
        keep_response(summary, after, threshold, introduced~),
        brief=success_brief(writes),
      )
    }
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
/// never reported as a clean rollback. The containment scope gates these
/// restore/re-apply writes too — a path whose resolution changed since the
/// batch was admitted is skipped and reported rather than written blind.
async fn write_files(
  writes : Array[PreparedWrite],
  content : (PreparedWrite) -> String,
  write_scope? : @write_scope.WriteScope,
) -> Array[String] {
  let failures : Array[String] = []
  for write in writes {
    if write_scope is Some(scope) && scope.deny_reason(write.path) is Some(_) {
      failures.push(write.path)
      continue
    }
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
  let first_errors = after.first_errors()
  if first_errors.is_empty() {
    header
  } else {
    "\{header}\n\{first_errors.join("\n")}"
  }
}

///|
/// Evidence on whether the pre- and post-batch error counts are comparable.
///
/// `moon check` skips the dependents of a failing package, so a batch that
/// fixes the errors moon stopped at lets the build reach those dependents and
/// report errors that were always there; the count then rises without
/// breakage. A count delta cannot tell that from an over-match, but error
/// identities, locations and moon's package graph can, to a point:
///
/// - a new error INSIDE an edited file is an over-match;
/// - a new error in another file of an edited package that had NO pre-batch
///   errors, or in a package that depends on such a package, is breakage:
///   that code compiled cleanly before, so only the batch can have changed it;
/// - a new error in a package independent of everything edited cannot be
///   caused by the batch — certified reach;
/// - a new error in a package that depends on a package the batch FIXED is
///   ambiguous: moon had skipped that package, so the error may be pre-existing
///   or a caller broken by a changed signature; only the model can tell.
///
/// Every field is evidence; `verdict` turns them into one of five outcomes.
priv struct Comparability {
  // The pre-batch run's error count; `None` when that run could not be made
  // (then every post-batch error was counted as introduced).
  before_count : Int?
  // Pre-batch errors (by `ErrorSite::identity`) still reported after.
  remaining : Int
  // New errors inside a file this batch wrote — the signature of an over-match.
  new_in_edited : Array[String]
  // New errors in code that compiled cleanly before and depends on (or shares
  // a package with) something this batch edited — caused by the batch.
  new_breaking : Array[String]
  // New errors in packages that depend on a package this batch fixed,
  // including that package's own other files: its tests and siblings were
  // not necessarily compiled while it was broken. Either surfacing or broken
  // by the fix.
  new_in_dependents : Array[String]
  // New errors in packages independent of everything edited — cannot be
  // caused by the batch.
  new_independent : Int
  // New errors that could not be placed: no path, or a path in no package
  // moon knows from the checked project.
  unlocated : Int
  // Edited files outside every package of the checked project: the check ran
  // somewhere the batch did not edit, so its silence about them proves nothing.
  unmapped_edits : Int
  // A `moon.mod`/`moon.work` edit can change what every package sees; the
  // package graph then says nothing about causation.
  module_manifest_edited : Bool
  // moon produced the package graph the classification above relies on.
  graph_available : Bool
  // Either run overflowed the capture budget, so the identity sets are
  // incomplete and no conclusion is drawn from them.
  truncated : Bool
}

///|
/// What the evidence adds up to, in precedence order: positive proof of
/// breakage first, then missing information, then the two reach outcomes.
priv enum Verdict {
  // New errors inside an edited file.
  OverMatch
  // New errors in code that compiled cleanly before and depends on the edit.
  Breakage
  // The comparison cannot be trusted either way; carries the reason.
  Inconclusive(String)
  // Every new error is in a package independent of the edit.
  CertifiedReach
  // Some new errors are in packages that depend on what the batch fixed.
  PlausibleReach
} derive(Debug, Eq)

///|
fn Comparability::verdict(self : Comparability) -> Verdict {
  if !self.new_in_edited.is_empty() {
    return OverMatch
  }
  if !self.new_breaking.is_empty() {
    return Breakage
  }
  match self.before_count {
    None =>
      return Inconclusive(
        "the pre-batch check could not run, so every post-batch error was counted as introduced",
      )
    Some(0) =>
      return Inconclusive(
        "the tree checked clean before this batch, so every post-batch error is attributable to it",
      )
    Some(_) => ()
  }
  if self.truncated {
    return Inconclusive(
      "check output was truncated, so the error identities are incomplete",
    )
  }
  if !self.graph_available {
    return Inconclusive(
      "moon could not report the package graph, so new errors outside the edited files cannot be attributed",
    )
  }
  if self.module_manifest_edited {
    return Inconclusive(
      "the batch edits a module manifest (moon.mod/moon.work), which can change what every package sees",
    )
  }
  if self.unmapped_edits > 0 {
    return Inconclusive(
      "\{self.unmapped_edits} edited file(s) lie outside every package of the checked project, so the check never covered them",
    )
  }
  if self.unlocated > 0 {
    return Inconclusive(
      "\{self.unlocated} new error(s) could not be placed in any package",
    )
  }
  if self.new_in_dependents.is_empty() {
    CertifiedReach
  } else {
    PlausibleReach
  }
}

///|
/// A write target as moon might name it in a diagnostic. `spellings` are the
/// path as written, its directory canonicalized with the written name, and
/// the full realpath — moon reports the canonical directory (on macOS an edit
/// under `/tmp/…` is diagnosed under `/private/tmp/…`) but the file under the
/// name it compiled, so an edited `alias.mbt -> source.txt` is diagnosed as
/// `…/alias.mbt`. `canonical` is the spelling used to find the file's package.
priv struct EditedTarget {
  spellings : Array[String]
  canonical : String
}

///|
/// Resolve every write target's spellings. A path realpath cannot resolve
/// contributes what it can.
async fn edited_targets(writes : Array[PreparedWrite]) -> Array[EditedTarget] {
  let targets : Array[EditedTarget] = []
  for write in writes {
    let spellings : Array[String] = [write.path]
    let mut canonical = write.path
    if write.path.rev_split_once("/") is Some((dir, name)) && dir != "" {
      let canonical_dir = @fs.realpath(dir) catch {
        error if @async.is_being_cancelled() => raise error
        _ => dir.to_owned()
      }
      canonical = "\{canonical_dir}/\{name}"
      spellings.push(canonical)
    }
    let resolved = @fs.realpath(write.path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => {
        targets.push({ spellings, canonical, })
        continue
      }
    }
    spellings.push(resolved)
    targets.push({ spellings, canonical, })
  }
  targets
}

///|
/// Gather the evidence for a batch that breached the threshold: the project
/// moon checked from (`check_path`'s), its package graph, and the batch's
/// resolved targets, then classify.
async fn gather_comparability(
  check_path : String,
  before : @auto_check.CheckErrors?,
  after : @auto_check.CheckErrors,
  writes : Array[PreparedWrite],
) -> Comparability {
  let cwd = @auto_check.check_cwd(check_path)
  let graph = match cwd {
    Some(cwd) =>
      @auto_check.package_graph(cwd) catch {
        error if @async.is_being_cancelled() => raise error
        _ => None
      }
    None => None
  }
  comparability(before, after, edited_targets(writes), cwd~, graph~)
}

///|
/// Pure classification of the two runs against the batch's targets. `cwd`
/// absolutizes moon's relative diagnostic paths; `graph` places paths in
/// packages and answers dependency questions.
fn comparability(
  before : @auto_check.CheckErrors?,
  after : @auto_check.CheckErrors,
  edited : Array[EditedTarget],
  cwd~ : String?,
  graph~ : @auto_check.PackageGraph?,
) -> Comparability {
  let seen : Set[String] = Set([])
  if before is Some(before) {
    for site in before.errors {
      seen.add(site.identity())
    }
  }
  let module_manifest_edited = edited.any(target => {
    let name = target.canonical.rev_after("/").unwrap_or(target.canonical)
    name == "moon.mod" || name == "moon.work"
  })
  // The packages this batch edited, and the subset that had pre-batch errors
  // (the ones the batch may have fixed, whose dependents moon skipped).
  let edited_pkgs : Array[Int] = []
  let mut unmapped_edits = 0
  if graph is Some(graph) {
    for target in edited {
      // Every spelling can name a package: a symlink's own directory AND its
      // target's — an edited `a/alias.mbt -> z/z.mbt` changes package `z`
      // too, so `z`'s dependents must count as depending on the edit.
      let mut mapped = false
      for spelling in target.spellings {
        guard graph.package_of(spelling) is Some(pkg) else { continue }
        mapped = true
        if !edited_pkgs.contains(pkg) {
          edited_pkgs.push(pkg)
        }
      }
      if !mapped {
        unmapped_edits += 1
      }
    }
  }
  let fixed_pkgs : Array[Int] = []
  if graph is Some(graph) && before is Some(before) {
    for site in before.errors {
      guard site.path is Some(path) else { continue }
      guard graph.package_of(absolutize(path, cwd)) is Some(pkg) else {
        continue
      }
      if edited_pkgs.contains(pkg) && !fixed_pkgs.contains(pkg) {
        fixed_pkgs.push(pkg)
      }
    }
  }
  let mut remaining = 0
  let mut unlocated = 0
  let mut new_independent = 0
  let new_in_edited : Array[String] = []
  let new_breaking : Array[String] = []
  let new_in_dependents : Array[String] = []
  for site in after.errors {
    if seen.contains(site.identity()) {
      remaining += 1
      continue
    }
    guard site.path is Some(path) else {
      unlocated += 1
      continue
    }
    let line = site.line()
    if edited.any(target => in_edited_file(path, target.spellings)) {
      new_in_edited.push(line)
      continue
    }
    guard graph is Some(graph) else { continue }
    guard graph.package_of(absolutize(path, cwd)) is Some(pkg) else {
      unlocated += 1
      continue
    }
    if edited_pkgs.contains(pkg) {
      // Another file of an edited package. If the package compiled cleanly
      // before, that file was compiled with the edit's file and a new error
      // here is the batch's doing. If the package was broken before, its
      // blackbox tests (a separate compilation unit that depends on it) and
      // possibly its siblings were skipped, so the error may be surfacing.
      if fixed_pkgs.contains(pkg) {
        new_in_dependents.push(line)
      } else {
        new_breaking.push(line)
      }
    } else if graph.depends_on(pkg, fixed_pkgs) {
      new_in_dependents.push(line)
    } else if graph.depends_on(pkg, edited_pkgs) {
      new_breaking.push(line)
    } else {
      new_independent += 1
    }
  }
  {
    before_count: before.map(b => b.error_count),
    remaining,
    new_in_edited,
    new_breaking,
    new_in_dependents,
    new_independent,
    unlocated,
    unmapped_edits,
    module_manifest_edited,
    graph_available: graph is Some(_),
    truncated: after.truncated || before.map(b => b.truncated).unwrap_or(false),
  }
}

///|
/// moon reports diagnostic paths relative to the checked project or absolute;
/// make them absolute so they can be placed in a package.
fn absolutize(path : String, cwd : String?) -> String {
  let absolute = path.has_prefix("/") || (path.length() > 1 && path[1:2] == ":")
  match cwd {
    Some(cwd) if !absolute => "\{cwd}/\{path}"
    _ => path
  }
}

///|
/// Whether a diagnostic's path (as moon reported it: relative to the checked
/// project, or absolute and canonical) names one of a target's spellings.
fn in_edited_file(diagnostic_path : String, spellings : Array[String]) -> Bool {
  spellings.any(path => {
    path == diagnostic_path ||
    path.has_suffix("/\{diagnostic_path}") ||
    path.has_suffix("\\\{diagnostic_path}")
  })
}

///|
/// How many sites of one class the revert report lists by name.
const SiteDisplayLimit : Int = 5

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
  evidence~ : Comparability,
) -> String {
  let total = total_edit_count(writes)
  let head = "reverted: applied \{total} edit(s) across \{writes.length()} file(s), but moon check then reported \{error_count_label(after)} error(s) (\{introduced} newly introduced > revert_when_errors_above=\{threshold}); all \{writes.length()} file(s) were rolled back to their pre-batch contents."
  let first_errors = after.first_errors()
  let errors = if first_errors.is_empty() {
    ""
  } else {
    "\nfirst \{first_errors.length()} error(s):\n\{first_errors.join("\n")}"
  }
  let restore_note = if restore_failures.is_empty() {
    ""
  } else {
    "\nWARNING: could not restore \{restore_failures.length()} file(s): \{restore_failures.join(", ")} — inspect them manually."
  }
  "\{head}\{errors}\{restore_note}\n\{comparability_advice(evidence, introduced~)}"
}

///|
/// List up to `SiteDisplayLimit` sites of one class, with an overflow note.
fn site_list(sites : Array[String]) -> String {
  let limit = if sites.length() < SiteDisplayLimit {
    sites.length()
  } else {
    SiteDisplayLimit
  }
  let shown = sites[:limit]
  let more = if sites.length() > shown.length() {
    "\n… \{sites.length() - shown.length()} more"
  } else {
    ""
  }
  "\n\{shown.join("\n")}\{more}"
}

///|
/// The re-issue instruction for a reach verdict, or why it cannot be given.
fn reissue_advice(introduced : Int) -> String {
  if introduced > HostMaxRevertThreshold {
    "The delta exceeds the host cap of revert_when_errors_above=\{HostMaxRevertThreshold}, so this batch cannot be admitted in one call: split it by package and let each part's check reach further."
  } else {
    "Re-issue the batch UNCHANGED with revert_when_errors_above=\{introduced}; it will then be kept and the remaining errors reported."
  }
}

///|
fn comparability_advice(evidence : Comparability, introduced~ : Int) -> String {
  let narrow = "re-issue with more precise old_strings (include the receiver) and/or smaller batches so a replacement cannot stray onto unintended sites."
  let pre_batch = match evidence.before_count {
    Some(count) if evidence.remaining == 0 =>
      "all \{count} pre-batch error(s) are gone"
    Some(count) =>
      "\{evidence.remaining} of \{count} pre-batch error(s) remain (the batch fixed the rest)"
    None => "no pre-batch baseline"
  }
  match evidence.verdict() {
    OverMatch =>
      "comparability: \{pre_batch}; \{evidence.new_in_edited.length()} new error(s) sit in files this batch edited (over-match evidence):\{site_list(evidence.new_in_edited)}\n\{narrow}"
    Breakage =>
      "comparability: \{pre_batch}; \{evidence.new_breaking.length()} new error(s) are in code that compiled cleanly before this batch and depends on (or shares a package with) what it edited, so the batch caused them — a changed signature or type?\{site_list(evidence.new_breaking)}\nfix the batch rather than raising revert_when_errors_above."
    Inconclusive(reason) =>
      "comparability: \{pre_batch}; inconclusive — \{reason}. The count comparison cannot be trusted either way, so the batch stays reverted; \{narrow}"
    CertifiedReach =>
      "comparability: \{pre_batch}, and none of the \{evidence.new_independent} new error(s) can be caused by this batch: per moon's package graph they are in packages that depend on nothing it edited, and none is in an edited file. moon check skips the dependents of a failing package, so the pre-batch run stopped short of them and this delta is a measurement artifact, not breakage. \{reissue_advice(introduced)}"
    PlausibleReach =>
      "comparability: \{pre_batch}; no new error is in an edited file; \{evidence.new_independent} new error(s) are in packages independent of everything edited (cannot be caused by the batch); \{evidence.new_in_dependents.length()} are in packages that depend on a package this batch FIXED — moon had skipped those packages while their dependency was broken, so each is either a pre-existing error surfacing or a caller broken by a changed signature/type in the fix, and the tool cannot tell which:\{site_list(evidence.new_in_dependents)}\nVerify those sites are the pre-existing class you are fixing (not callers of something this batch changed). If so: \{reissue_advice(introduced)} If not, fix the batch."
  }
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
fn sample_write(path : String, edits : Int) -> PreparedWrite {
  { path, new_content: "new", original_content: "old", edit_count: edits, }
}

///|
fn site(path : String, loc : String, message : String) -> @auto_check.ErrorSite {
  { path: Some(path), loc, code: None, message, }
}

///|
fn check_result(
  errors : Array[@auto_check.ErrorSite],
  truncated? : Bool = false,
) -> @auto_check.CheckErrors {
  { error_count: errors.length(), warning_count: 0, errors, truncated, }
}

///|
fn target(path : String) -> EditedTarget {
  { spellings: [path], canonical: path, }
}

///|
/// A project at `/r` with packages `x`, `y` (imports `x`), `z` (independent),
/// `w` (imports `z`), and `q` (imports `x` via a test import).
fn sample_graph() -> @auto_check.PackageGraph {
  {
    dirs: [Some("/r/x"), Some("/r/y"), Some("/r/z"), Some("/r/w"), Some("/r/q")],
    edges: [(1, 0), (3, 2), (4, 0)],
  }
}

///|
fn classify(
  before : @auto_check.CheckErrors?,
  after : @auto_check.CheckErrors,
  edited : Array[String],
) -> Comparability {
  comparability(
    before,
    after,
    edited.map(target),
    cwd=Some("/r"),
    graph=Some(sample_graph()),
  )
}

///|
/// Evidence of a clean pre-batch tree: inconclusive, so the report gives the
/// narrow-your-old_strings advice.
fn clean_tree_evidence() -> Comparability {
  classify(
    Some(check_result([])),
    check_result([site("z/z.mbt", "1:1-1:2", "e")]),
    ["/r/x/x.mbt"],
  )
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
    errors: [],
    truncated: false,
  }
  assert_eq(
    keep_response(summary, clean, 5),
    "\{summary}\nmoon check: ok — 0 errors, 12 warning(s)",
  )
  let kept : @auto_check.CheckErrors = {
    error_count: 2,
    warning_count: 12,
    errors: [site("a.mbt", "1:1-1:2", "boom"), site("a.mbt", "4:1-4:2", "bang")],
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
    errors: [site("a.mbt", "1:1-1:2", "boom")],
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
    errors: [site("a.mbt", "1:1-1:2", "boom"), site("b.mbt", "2:1-2:2", "bang")],
    truncated: false,
  }
  let report = revert_report(
    [sample_write("a.mbt", 4), sample_write("b.mbt", 2)],
    after,
    introduced=9,
    threshold=5,
    restore_failures=[],
    evidence=clean_tree_evidence(),
  )
  assert_eq(
    report,
    (
      #|reverted: applied 6 edit(s) across 2 file(s), but moon check then reported 9 error(s) (9 newly introduced > revert_when_errors_above=5); all 2 file(s) were rolled back to their pre-batch contents.
      #|first 2 error(s):
      #|a.mbt:1:1-1:2: boom
      #|b.mbt:2:1-2:2: bang
      #|comparability: all 0 pre-batch error(s) are gone; inconclusive — the tree checked clean before this batch, so every post-batch error is attributable to it. The count comparison cannot be trusted either way, so the batch stays reverted; re-issue with more precise old_strings (include the receiver) and/or smaller batches so a replacement cannot stray onto unintended sites.
    ),
  )
}

///|
test "revert_report marks a truncated count and a failed restore" {
  let after : @auto_check.CheckErrors = {
    error_count: 400,
    warning_count: 0,
    errors: [site("a.mbt", "1:1-1:2", "boom")],
    truncated: true,
  }
  let report = revert_report(
    [sample_write("a.mbt", 1)],
    after,
    introduced=400,
    threshold=5,
    restore_failures=["a.mbt"],
    evidence=clean_tree_evidence(),
  )
  assert_true(report.contains("reported ≥400 error(s)"))
  assert_true(report.contains("WARNING: could not restore 1 file(s): a.mbt"))
}

///|
/// The issue-#1452 shape: the pre-batch run stopped at 10 errors in the edited
/// package `x`; the batch fixed all 10, moon then compiled `y` (which imports
/// `x`), and 87 errors in `y` surfaced. By count that is "77 introduced"; by
/// the graph it is a reach through a dependent of the fixed package — real
/// but not certifiable, so the advice names the sites to vet and the value.
test "comparability calls new errors in dependents of a fixed package a plausible reach" {
  let before = check_result(
    [
      for index in 0..<10 => {
        site("x/x.mbt", "\{index + 1}:1-1:2", "wanted String")
      }
    ],
  )
  let after = check_result(
    [
      for index in 0..<87 => {
        site("y/y.mbt", "\{index + 1}:1-1:2", "wanted String")
      }
    ],
  )
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.remaining, 0)
  assert_eq(evidence.new_in_dependents.length(), 87)
  assert_eq(evidence.verdict(), PlausibleReach)
  let advice = comparability_advice(evidence, introduced=77)
  assert_true(advice.contains("all 10 pre-batch error(s) are gone"))
  assert_true(advice.contains("depend on a package this batch FIXED"))
  assert_true(advice.contains("y/y.mbt:1:1-1:2: wanted String"))
  assert_true(advice.contains("… 82 more"))
  assert_true(advice.contains("Verify those sites"))
  assert_true(
    advice.contains(
      "If so: Re-issue the batch UNCHANGED with revert_when_errors_above=77",
    ),
  )
  assert_false(advice.contains("more precise old_strings"))
  // Past the host cap the override cannot reach; say so instead of naming an
  // unreachable value.
  let capped = comparability_advice(
    evidence,
    introduced=HostMaxRevertThreshold + 1,
  )
  assert_true(
    capped.contains(
      "exceeds the host cap of revert_when_errors_above=\{HostMaxRevertThreshold}",
    ),
  )
  assert_false(capped.contains("UNCHANGED"))
}

///|
test "comparability certifies new errors in packages independent of the edit" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  // `z` and `w` import nothing edited; moon reports absolute paths here.
  let after = check_result([
    site("/r/z/z.mbt", "3:1-3:2", "e1"),
    site("/r/w/w.mbt", "4:1-4:2", "e2"),
  ])
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.new_independent, 2)
  assert_eq(evidence.verdict(), CertifiedReach)
  let advice = comparability_advice(evidence, introduced=1)
  assert_true(
    advice.contains("none of the 2 new error(s) can be caused by this batch"),
  )
  assert_true(
    advice.contains(
      "Re-issue the batch UNCHANGED with revert_when_errors_above=1",
    ),
  )
  assert_false(advice.contains("Verify those sites"))
}

///|
/// Review finding #3: a batch that fixes most but not all of the errors moon
/// stopped at must not be told to narrow itself when nothing points at it.
test "comparability keeps a partial fix on the reach path" {
  let before = check_result(
    [
      for index in 0..<10 => site("x/x.mbt", "\{index + 1}:1-1:2", "old")
    ],
  )
  let after = check_result(
    [
      ..[
        for index in 0..<4 => site("x/x.mbt", "\{index + 1}:1-1:2", "old")
      ],
      site("z/z.mbt", "1:1-1:2", "surfaced"),
    ],
  )
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.remaining, 4)
  assert_eq(evidence.verdict(), CertifiedReach)
  let advice = comparability_advice(evidence, introduced=1)
  assert_true(
    advice.contains(
      "4 of 10 pre-batch error(s) remain (the batch fixed the rest)",
    ),
  )
  assert_false(advice.contains("more precise old_strings"))
}

///|
test "comparability calls a break in code that compiled before the batch breakage" {
  // `x` had no pre-batch errors (the only one was in `z`, and it remains); a
  // new error in `y`, which imports `x`, can only be the batch's doing. So can
  // one in another file of `x` itself.
  let before = check_result([site("z/z.mbt", "1:1-1:2", "unrelated")])
  let after = check_result([
    site("z/z.mbt", "1:1-1:2", "unrelated"),
    site("y/y.mbt", "7:1-7:2", "caller broke"),
    site("x/other.mbt", "2:1-2:2", "sibling broke"),
    site("q/q_test.mbt", "5:1-5:2", "test import broke"),
  ])
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.remaining, 1)
  assert_eq(evidence.new_breaking, [
    "y/y.mbt:7:1-7:2: caller broke", "x/other.mbt:2:1-2:2: sibling broke", "q/q_test.mbt:5:1-5:2: test import broke",
  ])
  assert_eq(evidence.verdict(), Breakage)
  let advice = comparability_advice(evidence, introduced=3)
  assert_true(advice.contains("compiled cleanly before this batch"))
  assert_true(
    advice.contains(
      "fix the batch rather than raising revert_when_errors_above",
    ),
  )
  assert_false(advice.contains("UNCHANGED"))
}

///|
/// An edited symlink whose target lives in another package changes that
/// package too: `a/alias.mbt -> z/z.mbt` makes `w` (imports `z`) a dependent
/// of the edit, so a new error there is breakage when `z` was clean before.
test "comparability attributes through an edited symlink's target package" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result([site("w/w.mbt", "2:1-2:2", "caller broke")])
  let link : EditedTarget = {
    spellings: ["/r/x/alias.mbt", "/r/z/z.mbt"],
    canonical: "/r/x/alias.mbt",
  }
  let evidence = comparability(
    Some(before),
    after,
    [link],
    cwd=Some("/r"),
    graph=Some(sample_graph()),
  )
  assert_eq(evidence.new_breaking, ["w/w.mbt:2:1-2:2: caller broke"])
  assert_eq(evidence.verdict(), Breakage)
}

///|
/// A fixed package's own test file: its blackbox tests could not compile
/// while the package was broken, so their errors surfacing is a plausible
/// reach, not proven breakage.
test "comparability keeps a fixed package's other files on the plausible path" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result(
    [
      for index in 0..<12 => {
        site("x/x_test.mbt", "\{index + 1}:1-1:2", "surfaced")
      }
    ],
  )
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.new_breaking, [])
  assert_eq(evidence.new_in_dependents.length(), 12)
  assert_eq(evidence.verdict(), PlausibleReach)
  assert_true(
    comparability_advice(evidence, introduced=11).contains(
      "If so: Re-issue the batch UNCHANGED with revert_when_errors_above=11",
    ),
  )
}

///|
test "comparability treats new errors inside edited files as an over-match first" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result([
    site("x/x.mbt", "7:1-7:2", "stray"),
    site("x/x.mbt", "9:1-9:2", "stray"),
    site("z/z.mbt", "2:1-2:2", "independent"),
  ])
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.new_in_edited, [
    "x/x.mbt:7:1-7:2: stray", "x/x.mbt:9:1-9:2: stray",
  ])
  assert_eq(evidence.new_independent, 1)
  assert_eq(evidence.verdict(), OverMatch)
  let advice = comparability_advice(evidence, introduced=3)
  assert_true(advice.contains("2 new error(s) sit in files this batch edited"))
  assert_true(advice.contains("x/x.mbt:9:1-9:2: stray"))
  assert_true(advice.contains("more precise old_strings"))
  assert_false(advice.contains("UNCHANGED"))
}

///|
/// Review finding #2: a check that ran in a project the batch did not edit
/// can never see the edited files, so its silence about them proves nothing.
test "comparability never claims reach when an edited file is outside the checked project" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result([site("z/z.mbt", "2:1-2:2", "surfaced")])
  let evidence = classify(Some(before), after, [
    "/r/x/x.mbt", "/elsewhere/scripts/tool.mbt",
  ])
  assert_eq(evidence.unmapped_edits, 1)
  assert_true(evidence.verdict() is Inconclusive(_))
  let advice = comparability_advice(evidence, introduced=1)
  assert_true(
    advice.contains(
      "1 edited file(s) lie outside every package of the checked project",
    ),
  )
  assert_false(advice.contains("UNCHANGED"))
}

///|
test "comparability is inconclusive without a baseline, a graph, or complete output" {
  let elsewhere = check_result([site("z/z.mbt", "1:1-1:2", "surfaced")])
  let old = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  // Clean tree: it compiled everything, so the new errors are the batch's.
  assert_true(clean_tree_evidence().verdict() is Inconclusive(_))
  assert_true(
    comparability_advice(clean_tree_evidence(), introduced=1).contains(
      "checked clean before this batch",
    ),
  )
  // No baseline run at all.
  let missing = classify(None, elsewhere, ["/r/x/x.mbt"])
  assert_eq(missing.before_count, None)
  assert_true(
    comparability_advice(missing, introduced=1).contains(
      "pre-batch check could not run",
    ),
  )
  // Same shape as a reach, but the identity sets are partial.
  let truncated = classify(
    Some(check_result([site("x/x.mbt", "1:1-1:2", "old")], truncated=true)),
    elsewhere,
    ["/r/x/x.mbt"],
  )
  assert_true(truncated.truncated)
  assert_true(
    comparability_advice(truncated, introduced=1).contains(
      "error identities are incomplete",
    ),
  )
  // No package graph: nothing outside the edited files can be attributed.
  let no_graph = comparability(
    Some(old),
    elsewhere,
    [target("/r/x/x.mbt")],
    cwd=Some("/r"),
    graph=None,
  )
  assert_false(no_graph.graph_available)
  assert_true(
    comparability_advice(no_graph, introduced=1).contains(
      "could not report the package graph",
    ),
  )
  // A module manifest edit can change what every package sees.
  let manifest = classify(Some(old), elsewhere, ["/r/x/x.mbt", "/r/moon.mod"])
  assert_true(manifest.module_manifest_edited)
  assert_true(
    comparability_advice(manifest, introduced=1).contains(
      "edits a module manifest",
    ),
  )
  // A new error moon reported without a path, or in no known package, cannot
  // be placed, so it blocks the reach conclusion rather than counting as
  // "elsewhere".
  let nowhere = check_result([
    { path: None, loc: "2:1-2:2", code: None, message: "nowhere", },
    site("/outside/o.mbt", "1:1-1:2", "unknown package"),
  ])
  let unlocated = classify(Some(old), nowhere, ["/r/x/x.mbt"])
  assert_eq(unlocated.unlocated, 2)
  assert_true(
    comparability_advice(unlocated, introduced=2).contains(
      "2 new error(s) could not be placed in any package",
    ),
  )
}

///|
test "comparability compares by error code so a reworded message is not new" {
  let coded = fn(message : String) -> @auto_check.ErrorSite {
    { path: Some("x/x.mbt"), loc: "1:1-1:2", code: Some(4014), message, }
  }
  let evidence = classify(
    Some(check_result([coded("old wording")])),
    check_result([coded("new wording")]),
    ["/r/x/x.mbt"],
  )
  assert_eq(evidence.remaining, 1)
  assert_eq(evidence.new_in_edited, [])
}

///|
test "absolutize joins moon's relative paths onto the checked project" {
  assert_eq(absolutize("x/x.mbt", Some("/r")), "/r/x/x.mbt")
  assert_eq(absolutize("/private/r/x.mbt", Some("/r")), "/private/r/x.mbt")
  assert_eq(absolutize("C:\\r\\x.mbt", Some("/r")), "C:\\r\\x.mbt")
  assert_eq(absolutize("x/x.mbt", None), "x/x.mbt")
}

///|
test "in_edited_file matches moon's relative paths against a target's spellings" {
  let spellings = ["/ws/cmd/openseek/main.mbt", "C:\\ws\\lib\\win.mbt"]
  assert_true(in_edited_file("cmd/openseek/main.mbt", spellings))
  assert_true(in_edited_file("/ws/cmd/openseek/main.mbt", spellings))
  assert_true(in_edited_file("win.mbt", spellings))
  // A same-named file in another directory is not the edited one.
  assert_false(in_edited_file("other/main.mbt", spellings))
  assert_false(
    in_edited_file("openseek/main.mbt", ["/ws/cmd/xopenseek/main.mbt"]),
  )
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
