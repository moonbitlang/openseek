///|
/// Step ceiling requested for one explore child. Generous enough that a
/// scout answering a real question never dies mid-search (a truncated child
/// burns its whole allowance and returns nothing); the answer-early rule in
/// the prompt, not this ceiling, is what keeps exploration cheap.
pub let default_explore_max_steps : Int = 100

///|
/// Wall deadline for one explore child. A scout that has not answered in
/// ten minutes is lost, not thorough. Sized with the step ceiling: at the
/// few seconds per step observed in dogfood runs, a child must be able to
/// spend its full step allowance without dying by the clock instead.
let default_explore_deadline_ms : Int = 600_000

///|
/// Input caps: a question is a question, not a document.
let max_query_chars : Int = 2_000

///|
/// Hints cap, same reasoning as the query cap.
let max_hints_chars : Int = 2_000

///|
/// Tool definition for `explore`: delegate one self-contained question to a
/// read-only scout subagent and get back a bounded, cited answer.
///
/// The scout runs in a DEDICATED CHILD PROCESS: `self_exe` (the parent's
/// own executable — never PATH, so parent and child are the same binary and
/// the report's derived JSON codecs cannot drift) invoked as
/// `subrun explore`. The child's toolset is `read`, `mbtx` (both its
/// instrument for `moon ide doc` and friends and its way to check
/// language/stdlib behavior with a self-contained snippet; a per-child
/// scratch lab is the one writable place, where the scout may scaffold
/// throwaway projects to verify claims empirically), and `submit_answer` —
/// no edit tools, no nested subagent tools. The
/// child inherits the environment for its API key; model and endpoint ride
/// argv. Launching consumes one slot of the shared per-turn `SubrunBudget`
/// call allowance BEFORE the child exists; the child runs at its full step
/// ceiling.
///
/// Failure is graceful by contract: a child that produces no report, times
/// out, or exhausts the budget returns an is_error result telling the
/// parent to fall back to reading directly — never a broken turn.
pub fn definition(
  self_exe~ : String,
  model~ : @deepseek.Model,
  workspace_root~ : String,
  budget~ : @agent_subrun.SubrunBudget,
  api_url? : String,
  child_session? : @agent_subrun.ChildSession,
) -> @agent_tool.AgentToolDefinition {
  @agent_tool.AgentToolDefinition(
    name="explore",
    concurrent_safe=true,
    description=(
      #|Delegate ONE self-contained question to a read-only scout subagent and get a
      #|bounded, cited answer. Use it EARLY for unfamiliar cross-package work, fan-out
      #|searches, end-to-end traces, or MoonBit APIs you are not sure about. When a task
      #|has 2-3 independent discovery tracks, issue one non-overlapping explore call per
      #|track in the SAME step BEFORE tracing them yourself; the calls run concurrently.
      #|Good questions include where X is handled, how Y flows, who calls Z, which tests
      #|cover it, or what API a package offers. Include known paths or symbols as hints.
      #|For one direct lookup (one `moon ide doc` query or one focused file read), do it
      #|yourself. The scout cannot edit and returns file:line citations you can verify.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "The one question to answer, self-contained (the scout sees nothing else of this conversation).",
        },
        "hints": {
          "type": "string",
          "description": "Optional pointers: paths, package names, or symbols the scout should start from.",
        },
      },
      "required": ["query"],
    }),
    execute=Async(arguments => {
      execute(
        self_exe, model, workspace_root, budget, api_url, child_session, arguments,
      )
    }),
  )
}

///|
async fn execute(
  self_exe : String,
  model : @deepseek.Model,
  workspace_root : String,
  budget : @agent_subrun.SubrunBudget,
  api_url : String?,
  child_session : @agent_subrun.ChildSession?,
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "query": String(query), .. } && !query.is_blank() else {
    return @agent_tool.respond(
      "error: explore requires a non-empty string `query`",
      is_error=true,
    )
  }
  guard query.length() <= max_query_chars else {
    return @agent_tool.respond(
      "error: explore query exceeds \{max_query_chars} chars — ask one self-contained question",
      is_error=true,
    )
  }
  let hints : String? = match arguments {
    { "hints": String(hints), .. } if !hints.is_blank() => Some(hints)
    _ => None
  }
  guard !(hints is Some(h) && h.length() > max_hints_chars) else {
    return @agent_tool.respond(
      "error: explore hints exceed \{max_hints_chars} chars",
      is_error=true,
    )
  }
  // Reserve BEFORE launch: the allowance gates the launch slot; a granted
  // child always runs at the full explore ceiling.
  guard budget.reserve(default_explore_max_steps) is Some(granted_steps) else {
    return @agent_tool.respond(
      "explore budget exhausted for this turn — answer from what you already know, or read the files directly.",
      is_error=true,
      brief="explore (budget exhausted)",
    )
  }
  // API key rides the inherited environment, never argv (visible in ps).
  let args = [
    "subrun",
    "explore",
    "--model",
    "\{model}",
    "--max-steps",
    "\{granted_steps}",
  ]
  if api_url is Some(url) {
    args.push("--api-url")
    args.push(url)
  }
  let input : Json = match hints {
    Some(hints) => { "query": query, "hints": hints }
    None => { "query": query }
  }
  let result = @agent_subrun.run_subrun(
    command=self_exe,
    args~,
    input~,
    parse_report=parse_child_report,
    wall_deadline_ms=default_explore_deadline_ms,
    kind="explore",
    label=@agent_tool.brief_line(query, limit=48),
    cwd=workspace_root,
    child_session?,
  )
  // On external cancellation run_subrun re-raises before this line: the
  // reservation stays debited for the rest of the turn — deliberately
  // conservative, since the dead child's true spend is unknown.
  // The sub-run id in the brief pairs the result with its lifecycle
  // brackets — and, when the child persisted a transcript, names the
  // sibling session the viewer links to. Display-only: the model never
  // sees briefs.
  match result.value() {
    Some(report) =>
      @agent_tool.respond(
        render_report(report),
        brief="explore \{result.subrun_id()} (\{report.citations.length()} citation(s), \{result.steps_used()} step(s))",
      )
    None =>
      @agent_tool.respond(
        "explore produced no report (\{Repr(result.terminal())}) — fall back to reading directly.",
        is_error=true,
        brief="explore \{result.subrun_id()} (no report)",
      )
  }
}

///|
/// Parse-and-validate the child's report line: the same contract
/// `submit_answer` enforced in the child, re-checked at the trust boundary —
/// the line is same-binary JSON, but the parent still refuses an oversized
/// or malformed report rather than rendering it.
fn parse_child_report(json : Json) -> Result[ExploreReport, String] {
  match parse_submission(json) {
    Err(problems) => Err(problems.join("; "))
    Ok(report) => Ok(report)
  }
}

///|
/// The CHILD-side entry for `openseek subrun explore`: decode the input
/// line, run the scout kind in this process, and return the report (the
/// dispatch prints it as the final `subrun_report` line). `None` when the
/// child finished without a valid submission or the input is malformed.
pub async fn run_child(
  input : Json,
  api_key~ : String,
  model~ : @deepseek.Model,
  max_steps~ : Int,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  workspace_root? : String = ".",
  session_id? : String = "explore",
  append_item? : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  scratch_dir? : String,
) -> ExploreReport? {
  guard input is { "query": String(query), .. } && !query.is_blank() else {
    return None
  }
  let hints : String? = match input {
    { "hints": String(hints), .. } if !hints.is_blank() => Some(hints)
    _ => None
  }
  @agent_kind.execute_kind(
    session_id~,
    append_item?,
    system_prompt=explore_system_prompt(),
    task=explore_task(query, hints, scratch_dir),
    tools=captured => {
      @agent_tool.Tools([
        @read.definition(workspace_root~),
        @mbtx.definition(workspace_root~, read_only=true, scratch_dir?),
        submit_answer_tool(captured),
      ])
    },
    max_steps~,
    api_key~,
    model~,
    thinking~,
    api_url?,
    workspace_root~,
  )
}

///|
/// Render the bounded report as the tool result. Every field was capped at
/// submission, so the rendered whole stays far below the loop's 60K clamp.
fn render_report(report : ExploreReport) -> String {
  let out = StringBuilder()
  out <+ "\{report.answer}"
  if report.citations.length() > 0 {
    out <+ "\n\nCitations:"
    for citation in report.citations {
      let line = citation.line.map(line => ":\{line}").unwrap_or("")
      let note = citation.note.map(note => " — \{note}").unwrap_or("")
      out <+ "\n- \{citation.file}\{line}\{note}"
    }
  }
  if report.unresolved is Some(unresolved) {
    out <+ "\n\nUnresolved: \{unresolved}"
  }
  out.to_string()
}

///|
test "render_report shows answer, citations, and unresolved" {
  let rendered = render_report(sample_report())
  assert_true(rendered.contains("Buffer::to_bytes"))
  assert_true(rendered.contains("- protocol/event.mbt:14 — Event enum"))
  assert_true(rendered.contains("- moonbitlang/core/buffer"))
  assert_true(rendered.contains("Unresolved: did not check the js backend"))
}

///|
test "parse_child_report re-checks the contract at the trust boundary" {
  guard parse_child_report(ToJson::to_json(sample_report())) is Ok(_) else {
    fail("expected a valid report")
  }
  guard parse_child_report({ "answer": "no version" }) is Err(_) else {
    fail("expected a parse rejection")
  }
  guard parse_child_report(ToJson::to_json({ ..sample_report(), answer: "", }))
    is Err(_) else {
    fail("expected a validation rejection")
  }
}
