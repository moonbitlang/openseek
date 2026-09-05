///|
/// Default step budget for one goal audit: leaner than a full review — the
/// audit reads the worktree against one goal, it does not survey a branch.
/// Sized so auditing a real workspace (read sources, run the project's own
/// checks) fits without the child dying at its ceiling unreported.
pub let default_audit_max_steps : Int = 100

// `audit_system_prompt()` — the read-only skeptic asking one question, does
// the worktree actually satisfy the goal the agent just recorded as met? —
// is generated from `audit_system_prompt.mbt.md` by the `md_to_mbt_string`
// dev_build rule (see moon.pkg). Edit the markdown, not the generated
// `.mbt`.

///|
/// The audit task: the goal text plus whatever baseline anchor exists.
fn audit_task(
  goal : String,
  baseline : @agent_session.GoalBaseline?,
  scratch_dir : String?,
) -> String {
  let lab = match scratch_dir {
    Some(lab) =>
      (
        $|
        $|Your scratch lab (writable): \{lab}
        $|Create files and projects THERE and run any moon command there to
        $|verify a claim empirically before reporting it. The worktree under
        $|audit stays read-only.
      )
    None => ""
  }
  let anchor = match baseline {
    Some(baseline) =>
      if baseline.dirty {
        (
          $|The worktree sat on commit \{baseline.sha} when this goal was set,
          $|and was ALREADY DIRTY then — `git diff \{baseline.sha}` overstates
          $|this goal's work; treat it as supporting context only.
        )
      } else {
        (
          $|The worktree sat on commit \{baseline.sha} (clean) when this goal
          $|was set: `git diff \{baseline.sha}` plus untracked files is a good
          $|approximation of this goal's work. Supporting context — the
          $|worktree itself is what you audit.
        )
      }
    None =>
      (
        #|No baseline was captured for this goal: audit the worktree on its
        #|own terms (`git status --porcelain`, working-tree diffs, the files).
      )
  }
  (
    $|The criteria under audit (a standing goal, or the caller's stated
    $|focus):
    $|\{goal}
    $|
    $|\{anchor}
    $|\{lab}
    $|Audit the current worktree against the goal's own criteria and
    $|submit_review once, with scope.head = "WORKTREE".
  )
}

///|
/// Run the goal audit IN THIS PROCESS (the `openseek subrun review` child
/// mode calls this; the standalone shape mirrors `run_review`). `None`
/// when the auditor finished without a valid submission.
pub async fn run_goal_audit(
  goal~ : String,
  baseline~ : @agent_session.GoalBaseline?,
  api_key~ : String,
  model~ : @deepseek.Model,
  max_steps~ : Int,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  workspace_root? : String = ".",
  session_id? : String = "goal-audit",
  append_item? : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  scratch_dir? : String,
) -> ReviewReport? {
  @agent_subrun.execute_kind(
    session_id~,
    append_item?,
    system_prompt=audit_system_prompt(),
    task=audit_task(goal, baseline, scratch_dir),
    tools=captured => {
      @agent_tool.Tools([
        @read.definition(workspace_root~),
        @mbtx.definition(workspace_root~, read_only=true, scratch_dir?),
        submit_review_tool(captured),
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
/// Digest bounds: the gate injects this into the model's context and the
/// durable log UNCLAMPED, so the caps live here, not in hope.
let digest_max_findings : Int = 10

///|
/// Per-finding line cap in the digest.
let digest_max_line_chars : Int = 200

///|
/// Total digest cap: the notice enters model context and the durable log
/// unclamped, so this bound is the only one.
let digest_max_chars : Int = 4_000

///|
/// The bounded `[review]` notice for a report: severity tally, trimmed
/// summary, and up to `digest_max_findings` one-line findings with an
/// explicit omission count — never more than `digest_max_chars` total.
pub fn ReviewReport::digest(self : ReviewReport) -> String {
  let blockers = self.findings.count_if(f => f.severity == "blocker")
  let highs = self.findings.count_if(f => f.severity == "high")
  let out = StringBuilder()
  out <+ "[review] worktree audit: \{self.findings.length()} finding(s)"
  if blockers > 0 || highs > 0 {
    out <+ " (\{blockers} blocker, \{highs} high)"
  }
  out <+ " — \{@agent_tool.brief_line(self.summary, limit=160)}"
  let shown = self.findings.length().min(digest_max_findings)
  for index in 0..<shown {
    let finding = self.findings[index]
    let line = finding.line.map(line => ":\{line}").unwrap_or("")
    let entry = @agent_tool.brief_line(
      "[\{finding.severity}] \{finding.file}\{line} — \{finding.title}",
      limit=digest_max_line_chars,
    )
    // The total cap wins over per-line room: stop before overflowing,
    // reserving room for the trailers appended below (~200 chars).
    if out.to_string().length() + entry.length() + 200 > digest_max_chars {
      out <+ "\n… digest cap reached"
      break
    }
    out <+ "\n- \{entry}"
  }
  if self.findings.length() > shown {
    out <+ "\n+\{self.findings.length() - shown} more finding(s) in the audit"
  }
  if blockers > 0 {
    out <+
      "\nA blocker means the audited claim does NOT hold: address it or explain why the audit is wrong before finishing."
  }
  out.to_string()
}

///|
test "digest is bounded and counts severities" {
  let many : Array[Finding] = []
  for index in 0..<25 {
    many.push({
      file: "src/file\{index}.mbt",
      line: Some(index),
      severity: if index < 2 {
        "blocker"
      } else {
        "low"
      },
      category: "correctness",
      title: "finding number \{index} with a reasonably descriptive title",
      detail: "detail",
      suggestion: None,
    })
  }
  let report : ReviewReport = {
    schema_version: 1,
    scope: { base: "abc", head: "WORKTREE", files: [], },
    findings: many,
    summary: "many findings",
    stats: { files_reviewed: 5, findings: 25, build: "pass", tests: "fail", },
  }
  let digest = report.digest()
  assert_true(digest.length() <= digest_max_chars)
  assert_true(
    digest.contains("worktree audit: 25 finding(s) (2 blocker, 0 high)"),
  )
  assert_true(digest.contains("+15 more finding(s)"))
  assert_true(digest.contains("does NOT hold"))
}

///|
test "a clean digest is one line of good news" {
  let report : ReviewReport = {
    schema_version: 1,
    scope: { base: "abc", head: "WORKTREE", files: ["a.mbt"], },
    findings: [],
    summary: "goal satisfied; tests pass",
    stats: { files_reviewed: 3, findings: 0, build: "pass", tests: "pass", },
  }
  let digest = report.digest()
  assert_true(digest.contains("0 finding(s)"))
  assert_false(digest.contains("blocker"))
}
