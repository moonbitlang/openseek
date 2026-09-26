///|
/// A registered one-shot preset: a bounded agent with its own restricted tools
/// and a typed report, chosen by name. A name that is not here is an error;
/// it never falls back to the general agent, which can do more.
priv enum Kind {
  /// The read-only scout: answers a question about the workspace.
  Explore
  /// The goal audit behind the review gate.
  Review
  /// A write-capable child confined to a provisioned git worktree.
  Worker
  /// A candidate-only structural pattern repair.
  PatternRepair
  /// A modelless probe that echoes its input as the report.
  Echo
}

///|
fn Kind::parse(name : StringView) -> Kind? {
  match name {
    "explore" => Some(Explore)
    "review" => Some(Review)
    "worker" => Some(Worker)
    "pattern-repair" => Some(PatternRepair)
    "echo" => Some(Echo)
    _ => None
  }
}

///|
/// Why `input` is not this kind's input, or `None` when it is. Pure, so a
/// request can be refused before anything is created for it.
fn Kind::check_input(self : Kind, input : Json) -> String? {
  match self {
    Explore =>
      if input is { "query": String(query), .. } && !query.is_blank() {
        None
      } else {
        Some("explore requires a non-empty query")
      }
    Review =>
      if input is { "goal": String(goal), .. } && !goal.is_blank() {
        None
      } else {
        Some("review requires a non-empty goal")
      }
    Worker =>
      match @agent_worker.WorkerInput::parse(input) {
        Ok(_) => None
        Err(reason) => Some(reason)
      }
    PatternRepair =>
      if input
        is {
          "pattern": String(pattern),
          "instruction": String(instruction),
          ..
        } &&
        !pattern.is_blank() &&
        !instruction.is_blank() {
        None
      } else {
        Some("pattern-repair requires pattern and instruction")
      }
    Echo => None
  }
}

///|
/// How running a kind went, short of an error (errors raise).
priv enum KindOutcome {
  /// The input was refused before any model was contacted; says why.
  Rejected(String)
  /// The kind's model turn ran; `report` is what it submitted, if anything.
  Ran(report~ : Json?)
  /// The modelless `echo` kind returned its input.
  Echoed(Json)
}

///|
/// What a kind's run needs from its launch. `requested_max_steps` is the
/// caller's per-request step ceiling, when its request carried one.
priv struct KindLaunch {
  matches : @argparse.Matches
  model : @deepseek.Model
  thinking : @deepseek.ThinkingMode
  api_url : String?
  workspace_root : String
  requested_max_steps : Int?
  session_id : String
  append_item : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session
}

///|
/// The step ceiling for one kind run: `resolved_max_steps`, else the kind's
/// own default.
fn step_ceiling(
  matches : @argparse.Matches,
  requested : Int?,
  default : Int,
) -> Int raise {
  resolved_max_steps(matches, requested).unwrap_or(default)
}

///|
/// Run `kind` on `input` in this process. Input is validated before an API key
/// is required, so a miswired caller learns the exact defect even keylessly.
/// Every model-driven kind but `worker` gets its own scratch lab: a temporary
/// directory where the otherwise read-only child may scaffold projects and
/// write source to check its claims.
async fn Kind::run(
  self : Kind,
  input : Json,
  launch : KindLaunch,
) -> KindOutcome {
  if self.check_input(input) is Some(reason) {
    return Rejected(reason)
  }
  let { matches, model, thinking, api_url, workspace_root, .. } = launch
  let (retry_attempts, retry_backoff_ms) = @options.retry_overrides(matches)
  fn api_key() raise {
    guard model.api_key(matches.values) is Some(api_key) else {
      fail("an API key is required for \{model}: pass --api-key")
    }
    api_key
  }
  match self {
    Explore => {
      let api_key = api_key()
      let scratch_dir = @setup.new_scratch_lab("openseek-explore-lab-")
      defer @setup.remove_scratch_lab(scratch_dir)
      let report = @agent_explore.run_child(
        input,
        api_key~,
        model~,
        max_steps=step_ceiling(
          matches,
          launch.requested_max_steps,
          @agent_explore.default_explore_max_steps,
        ),
        thinking~,
        api_url?,
        retry_attempts?,
        retry_backoff_ms?,
        workspace_root~,
        session_id=launch.session_id,
        append_item=launch.append_item,
        scratch_dir~,
      )
      Ran(report=report.map(report => Json(report)))
    }
    Review => {
      guard input is { "goal": String(goal), .. } else {
        return Rejected("review requires a non-empty goal")
      }
      let baseline : @agent_session.GoalBaseline? = match input {
        { "sha": String(sha), "dirty": dirty, .. } =>
          Some({ sha, dirty: dirty is True, })
        _ => None
      }
      let api_key = api_key()
      let scratch_dir = @setup.new_scratch_lab("openseek-review-lab-")
      defer @setup.remove_scratch_lab(scratch_dir)
      let report = @agent_review.run_goal_audit(
        goal~,
        baseline~,
        api_key~,
        model~,
        max_steps=step_ceiling(
          matches,
          launch.requested_max_steps,
          @agent_review.default_audit_max_steps,
        ),
        thinking~,
        api_url?,
        retry_attempts?,
        retry_backoff_ms?,
        workspace_root~,
        session_id=launch.session_id,
        append_item=launch.append_item,
        scratch_dir~,
      )
      Ran(report=report.map(report => Json(report)))
    }
    Worker => {
      let api_key = api_key()
      // No scratch lab: the worker's whole worktree is writable, and its
      // geometry (worktree, denied roots, allowed paths) arrives in the
      // input from the worker controller — the child enforces with what it
      // was handed rather than deriving anything itself.
      match
        @agent_worker.run_child(
          input,
          api_key~,
          model~,
          max_steps=step_ceiling(
            matches,
            launch.requested_max_steps,
            @agent_worker.default_worker_max_steps,
          ),
          thinking~,
          api_url?,
          retry_attempts?,
          retry_backoff_ms?,
          session_id=launch.session_id,
          append_item=launch.append_item,
        ) {
        Ok(report) => Ran(report=report.map(report => Json(report)))
        Err(reason) => Rejected(reason)
      }
    }
    PatternRepair => {
      guard input
        is {
          "pattern": String(pattern),
          "instruction": String(instruction),
          ..
        } else {
        return Rejected("pattern-repair requires pattern and instruction")
      }
      let api_key = api_key()
      let report = @agent_pattern_repair.run(
        pattern,
        instruction,
        api_key~,
        model~,
        // Pattern repair is bounded by its host's wall timeout. Keep the
        // agent loop unbounded by default so a repair can validate, inspect
        // the diagnostic, and retry as many times as needed.
        max_steps=step_ceiling(
          matches,
          launch.requested_max_steps,
          @agent.unbounded_max_steps,
        ),
        thinking~,
        api_url?,
        retry_attempts?,
        retry_backoff_ms?,
        workspace_root~,
        session_id=launch.session_id,
        append_item=launch.append_item,
      )
      Ran(report=report.map(report => Json(report)))
    }
    Echo => {
      // Two canned events plus the input echoed back: enough to exercise
      // spawn, drain, accounting, and the typed report channel end to end.
      @emit.emit(AgentStep(step=1))
      @emit.emit(
        Usage(usage={
          prompt_tokens: 7,
          completion_tokens: 3,
          total_tokens: 10,
          prompt_cache_hit_tokens: 0,
          prompt_cache_miss_tokens: 7,
        }),
      )
      Echoed(input)
    }
  }
}
