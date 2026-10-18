///|
/// What a background job is when it is a subagent: a child agent the engine
/// launched, carried on its `JobRecord` so a host can show it as an agent
/// rather than as a command.
///
/// The job's own `state` stays the fact about the PROCESS; `outcome` is what
/// the child achieved. `outcome`, `usage` and `report` are absent while the
/// child is live and settled once it has ended.
pub(all) struct SubagentInfo {
  /// The preset the child runs: `explore`, `review`, ...
  kind : String
  /// A short human label for the child's task.
  label : String
  /// The child's own durable session, `<parent>-sr-N`.
  session : String
  /// Who started the child, which is also who owns it.
  launch : SubagentLaunch
  /// How the child ended; `None` while it is live.
  outcome : SubagentOutcome?
  /// What the child spent; `None` while it is live.
  usage : SubagentUsage?
  /// Where its report is; `None` unless it ended `Captured`.
  report : SubagentReport?
  /// The checkout the child works in.
  workspace : SubagentWorkspace
} derive(Eq, Debug)

///|
/// Who started a subagent. The starter is its owner.
pub(all) enum SubagentLaunch {
  /// The model's own tool call. The child belongs to the session.
  Direct
  /// A script's host-tool call: the host's id for that script's program,
  /// and which of that program's subagent starts this is (from 0).
  Script(program~ : String, call~ : Int32)
} derive(Eq, Debug)

///|
/// How a subagent ended.
pub(all) enum SubagentOutcome {
  /// It submitted a report that passed its kind's validation.
  Captured
  /// It finished its turn without submitting a report.
  NoReport
  /// Its step budget ran out first.
  MaxSteps
  /// It filled its context window first.
  ContextYield
  /// Its launcher's wall deadline ran out first.
  TimedOut
  /// It was stopped: by a job stop, its owner closing, or shutdown.
  Stopped
  /// Anything else, with the reason.
  Failed(String)
} derive(Eq, Debug)

///|
/// What a subagent spent, once it has ended.
pub(all) enum SubagentUsage {
  /// The counts, from the child's own account or reconstructed. `steps`
  /// is `None` when the account did not say.
  Known(
    steps~ : Int32?,
    prompt_tokens~ : Int32,
    completion_tokens~ : Int32,
    cost_usd~ : Double?,
    source~ : SubagentUsageSource,
    unaccounted~ : String?
  )
  /// Nothing could be read; why.
  Unavailable(String)
} derive(Eq, Debug)

///|
/// Where a subagent's usage counts came from.
pub(all) enum SubagentUsageSource {
  /// The child's own result file: exact for the requests it made.
  Result
  /// Summed from the child's transcript because it left no result: a lower
  /// bound when `unaccounted` says so.
  Transcript
} derive(Eq, Debug)

///|
/// Where a captured report is.
pub(all) enum SubagentReport {
  /// In `report.json` in the child's session directory.
  Stored
  /// Storing it failed, with the reason. The engine that captured it still
  /// holds it in memory.
  StoreFailed(String)
} derive(Eq, Debug)

///|
/// The checkout a subagent works in.
pub(all) enum SubagentWorkspace {
  /// The session's own checkout, the one its launcher works in.
  InPlace
  /// A git worktree the engine provisioned for it, as of the record.
  Worktree(Worktree)
} derive(Eq, Debug)

///|
/// A worker's git worktree: a branch forked from the launching checkout's
/// HEAD, on which the engine commits the worker's changes once they pass
/// validation, and which the launching checkout may integrate.
///
/// The engine's registry, not a job record, is where its later states live:
/// a change after the job ended is published as `WorkerChanged`.
pub(all) struct Worktree {
  /// The slice's name, unique among the repository's active worktrees.
  name : String
  /// The worktree's root directory.
  path : String
  branch : String
  /// The commit it was forked from.
  base : String
  /// The repository-relative path prefixes the worker may change.
  allowed_paths : Array[String]
  state : WorktreeState
} derive(Eq, Debug)

///|
/// Where a worker's changes stand.
pub(all) enum WorktreeState {
  /// The worker is running in it, or has not been captured yet.
  Working
  /// Capturing it failed in git itself, for these reasons; it is left as it
  /// was, to be captured again.
  CaptureFailed(reasons~ : Array[String])
  /// Its changes passed validation and are committed on the branch.
  Committed(commit~ : String)
  /// It changed nothing; the worktree is gone.
  NoChanges
  /// Its changes failed validation, for these reasons; the worktree is kept
  /// for inspection.
  Unmergeable(defects~ : Array[String])
  /// Integrating it hit conflicts, which the launching checkout holds.
  Conflicted(commit~ : String)
  /// It was merged into the launching checkout; the worktree is gone.
  Integrated
  /// It was abandoned; the worktree and branch are gone.
  Discarded
} derive(Eq, Debug)

///|
fn subagent_count(
  fields : Map[String, Json],
  name : String,
  path : @json.JsonPath,
) -> Int32 raise @json.JsonDecodeError {
  let value = job_uint(fields, name, path)
  guard value <= 2147483647L else {
    raise JsonDecodeError((path, "subagent count out of range: " + name))
  }
  value.to_int()
}

///|
/// A session id the session store accepts: not empty, not `.` or `..`, and
/// without path separators or NUL. Broader than a job artifact name: a
/// session may be named with spaces or any Unicode.
fn valid_session_id(id : String) -> Bool {
  !(id is ("" | "." | "..")) &&
  !id.contains("/") &&
  !id.contains("\\") &&
  !id.contains("\u{0}")
}

///|
pub impl ToJson for SubagentLaunch with fn to_json(self) {
  match self {
    Direct => { "kind": "direct" }
    Script(program~, call~) =>
      { "kind": "script", "program": program, "call": call }
  }
}

///|
pub impl FromJson for SubagentLaunch with fn from_json(json, path) {
  match json {
    { "kind": "direct", .. } => Direct
    Object({ "kind": "script", "program": String(program), .. } as fields) if !program.is_empty() =>
      Script(program~, call=subagent_count(fields, "call", path))
    _ => raise JsonDecodeError((path, "invalid subagent launch"))
  }
}

///|
pub impl ToJson for SubagentOutcome with fn to_json(self) {
  match self {
    Captured => { "kind": "captured" }
    NoReport => { "kind": "no_report" }
    MaxSteps => { "kind": "max_steps" }
    ContextYield => { "kind": "context_yield" }
    TimedOut => { "kind": "timed_out" }
    Stopped => { "kind": "stopped" }
    Failed(reason) => { "kind": "failed", "reason": reason }
  }
}

///|
pub impl FromJson for SubagentOutcome with fn from_json(json, path) {
  match json {
    { "kind": "captured", .. } => Captured
    { "kind": "no_report", .. } => NoReport
    { "kind": "max_steps", .. } => MaxSteps
    { "kind": "context_yield", .. } => ContextYield
    { "kind": "timed_out", .. } => TimedOut
    { "kind": "stopped", .. } => Stopped
    { "kind": "failed", "reason": String(reason), .. } if !reason.is_empty() =>
      Failed(reason)
    _ => raise JsonDecodeError((path, "invalid subagent outcome"))
  }
}

///|
pub impl ToJson for SubagentUsage with fn to_json(self) {
  match self {
    Known(
      steps~,
      prompt_tokens~,
      completion_tokens~,
      cost_usd~,
      source~,
      unaccounted~
    ) => {
      let fields : Map[String, Json] = {
        "kind": "known",
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "source": match source {
          Result => "result"
          Transcript => "transcript"
        },
      }
      if steps is Some(steps) {
        fields["steps"] = Json(steps)
      }
      if cost_usd is Some(cost) {
        fields["cost_usd"] = Json(cost)
      }
      if unaccounted is Some(reason) {
        fields["unaccounted"] = Json(reason)
      }
      Json::object(fields)
    }
    Unavailable(reason) => { "kind": "unavailable", "reason": reason }
  }
}

///|
pub impl FromJson for SubagentUsage with fn from_json(json, path) {
  match json {
    Object({ "kind": "known", "source": String(source), .. } as fields) => {
      let source : SubagentUsageSource = match source {
        "result" => Result
        "transcript" => Transcript
        _ => raise JsonDecodeError((path, "invalid subagent usage source"))
      }
      let cost_usd : Double? = match fields.get("cost_usd") {
        None | Some(Null) => None
        Some(Number(cost, ..)) if cost >= 0.0 => Some(cost)
        Some(_) => raise JsonDecodeError((path, "invalid subagent cost"))
      }
      let steps = match fields.get("steps") {
        None | Some(Null) => None
        Some(_) => Some(subagent_count(fields, "steps", path))
      }
      Known(
        steps~,
        prompt_tokens=subagent_count(fields, "prompt_tokens", path),
        completion_tokens=subagent_count(fields, "completion_tokens", path),
        cost_usd~,
        source~,
        unaccounted=job_optional(fields, "unaccounted", path),
      )
    }
    { "kind": "unavailable", "reason": String(reason), .. } if !reason.is_empty() =>
      Unavailable(reason)
    _ => raise JsonDecodeError((path, "invalid subagent usage"))
  }
}

///|
pub impl ToJson for SubagentReport with fn to_json(self) {
  match self {
    Stored => { "kind": "stored" }
    StoreFailed(reason) => { "kind": "store_failed", "reason": reason }
  }
}

///|
pub impl FromJson for SubagentReport with fn from_json(json, path) {
  match json {
    { "kind": "stored", .. } => Stored
    { "kind": "store_failed", "reason": String(reason), .. } if !reason.is_empty() =>
      StoreFailed(reason)
    _ => raise JsonDecodeError((path, "invalid subagent report"))
  }
}

///|
pub impl ToJson for SubagentWorkspace with fn to_json(self) {
  match self {
    InPlace => { "kind": "in_place" }
    Worktree(worktree) => { "kind": "worktree", "worktree": worktree.to_json() }
  }
}

///|
pub impl FromJson for SubagentWorkspace with fn from_json(json, path) {
  match json {
    { "kind": "in_place", .. } => InPlace
    { "kind": "worktree", "worktree": worktree, .. } =>
      Worktree(Worktree::from_json(worktree, path))
    _ => raise JsonDecodeError((path, "invalid subagent workspace"))
  }
}

///|
pub impl ToJson for Worktree with fn to_json(self) {
  {
    "name": self.name,
    "path": self.path,
    "branch": self.branch,
    "base": self.base,
    "allowed_paths": self.allowed_paths,
    "state": self.state.to_json(),
  }
}

///|
pub impl FromJson for Worktree with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a worktree object"))
  }
  let name : String = job_required(fields, "name", path)
  let root : String = job_required(fields, "path", path)
  guard !name.is_empty() && !root.is_empty() else {
    raise JsonDecodeError((path, "invalid worktree name or path"))
  }
  {
    name,
    path: root,
    branch: job_required(fields, "branch", path),
    base: job_required(fields, "base", path),
    allowed_paths: job_required(fields, "allowed_paths", path),
    state: job_required(fields, "state", path),
  }
}

///|
pub impl ToJson for WorktreeState with fn to_json(self) {
  match self {
    Working => { "kind": "working" }
    CaptureFailed(reasons~) => { "kind": "capture_failed", "reasons": reasons }
    Committed(commit~) => { "kind": "committed", "commit": commit }
    NoChanges => { "kind": "no_changes" }
    Unmergeable(defects~) => { "kind": "unmergeable", "defects": defects }
    Conflicted(commit~) => { "kind": "conflicted", "commit": commit }
    Integrated => { "kind": "integrated" }
    Discarded => { "kind": "discarded" }
  }
}

///|
pub impl FromJson for WorktreeState with fn from_json(json, path) {
  match json {
    { "kind": "working", .. } => Working
    { "kind": "capture_failed", "reasons": reasons, .. } =>
      CaptureFailed(reasons=@json.from_json(reasons, path~))
    { "kind": "committed", "commit": String(commit), .. } if !commit.is_empty() =>
      Committed(commit~)
    { "kind": "no_changes", .. } => NoChanges
    { "kind": "unmergeable", "defects": defects, .. } =>
      Unmergeable(defects=@json.from_json(defects, path~))
    { "kind": "conflicted", "commit": String(commit), .. } if !commit.is_empty() =>
      Conflicted(commit~)
    { "kind": "integrated", .. } => Integrated
    { "kind": "discarded", .. } => Discarded
    _ => raise JsonDecodeError((path, "invalid worktree state"))
  }
}

///|
pub impl ToJson for SubagentInfo with fn to_json(self) {
  let fields : Map[String, Json] = {
    "kind": self.kind,
    "label": self.label,
    "session": self.session,
    "launch": self.launch.to_json(),
    "workspace": self.workspace.to_json(),
  }
  if self.outcome is Some(outcome) {
    fields["outcome"] = outcome.to_json()
  }
  if self.usage is Some(usage) {
    fields["usage"] = usage.to_json()
  }
  if self.report is Some(report) {
    fields["report"] = report.to_json()
  }
  Json::object(fields)
}

///|
pub impl FromJson for SubagentInfo with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a subagent object"))
  }
  let kind : String = job_required(fields, "kind", path)
  let session : String = job_required(fields, "session", path)
  guard !kind.is_empty() && valid_session_id(session) else {
    raise JsonDecodeError((path, "invalid subagent kind or session"))
  }
  {
    kind,
    label: job_required(fields, "label", path),
    session,
    launch: job_required(fields, "launch", path),
    outcome: job_optional(fields, "outcome", path),
    usage: job_optional(fields, "usage", path),
    report: job_optional(fields, "report", path),
    workspace: job_required(fields, "workspace", path),
  }
}

///|
pub extend SubagentInfo with Eq::{equal, not_equal}

///|
pub extend SubagentInfo with Debug::{to_repr}

///|
pub extend SubagentInfo with ToJson::{to_json}

///|
pub extend SubagentInfo with FromJson::{from_json}

///|
pub extend SubagentLaunch with Eq::{equal, not_equal}

///|
pub extend SubagentLaunch with Debug::{to_repr}

///|
pub extend SubagentOutcome with Eq::{equal, not_equal}

///|
pub extend SubagentOutcome with Debug::{to_repr}

///|
pub extend SubagentUsage with Eq::{equal, not_equal}

///|
pub extend SubagentUsage with Debug::{to_repr}

///|
pub extend SubagentUsageSource with Eq::{equal, not_equal}

///|
pub extend SubagentUsageSource with Debug::{to_repr}

///|
pub extend SubagentReport with Eq::{equal, not_equal}

///|
pub extend SubagentReport with Debug::{to_repr}

///|
pub extend SubagentWorkspace with Eq::{equal, not_equal}

///|
pub extend SubagentWorkspace with Debug::{to_repr}

///|
pub extend SubagentLaunch with ToJson::{to_json}

///|
pub extend SubagentLaunch with FromJson::{from_json}

///|
pub extend SubagentOutcome with ToJson::{to_json}

///|
pub extend SubagentOutcome with FromJson::{from_json}

///|
pub extend SubagentUsage with ToJson::{to_json}

///|
pub extend SubagentUsage with FromJson::{from_json}

///|
pub extend SubagentReport with ToJson::{to_json}

///|
pub extend SubagentReport with FromJson::{from_json}

///|
pub extend SubagentWorkspace with ToJson::{to_json}

///|
pub extend SubagentWorkspace with FromJson::{from_json}

///|
pub extend Worktree with Eq::{equal, not_equal}

///|
pub extend Worktree with Debug::{to_repr}

///|
pub extend Worktree with ToJson::{to_json}

///|
pub extend Worktree with FromJson::{from_json}

///|
pub extend WorktreeState with Eq::{equal, not_equal}

///|
pub extend WorktreeState with Debug::{to_repr}

///|
pub extend WorktreeState with ToJson::{to_json}

///|
pub extend WorktreeState with FromJson::{from_json}
