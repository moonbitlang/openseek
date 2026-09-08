///|
/// Capability eval for automatic background handoff. These prompts never
/// mention background jobs, `job_output`, or notices: the engine must move a
/// slow `mbtx` call after its foreground grace, while the model must use the
/// resulting time and job lifecycle sensibly:
///
/// - S1 "overlap": a ~20s command plus quick questions, with an efficiency
///   hint. Expected play: the slow command hands off automatically; answer the
///   quick questions while it runs, then fold in its result.
/// - S2 "fire and forget": a ~45s command the user explicitly does not want to
///   wait for. Expected play: let automatic handoff return the job id and end
///   the turn well under 45s.
///
/// The scorecard is informational (behavior varies run to run); the eval exits
/// non-zero only when the engine itself misbehaves. Run manually:
///
///   moon run --target native eval/bgjobs_capability
async fn main {
  // `DEEPSEEK` is the engine's API-key env var; blank means the engine would
  // reject it at startup, so both count as unset.
  guard @env.get_env_var("DEEPSEEK") is Some(key) && !key.is_blank() else {
    println("SKIP: DEEPSEEK is not set; this eval drives the live engine")
    return
  }
  @async.with_task_group(group => {
    let engine = Engine::spawn(group)
    scenario_overlap(engine)
    scenario_fire_and_forget(engine)
  })
}

///|
/// S1: the model is never told how — only that time matters. Judgment under
/// measurement: does automatic handoff occur, and does the model overlap the
/// quick work instead of waiting on the job immediately?
async fn scenario_overlap(engine : Engine) -> Unit {
  println("== S1 overlap: slow command + quick questions, efficiency hint ==")
  let started_ms = @env.now().reinterpret_as_int64()
  engine.prompt(
    (
      #|Please do all of the following, and be efficient with wall-clock time:
      #|1. Run the integration check. It takes about 20 seconds and then prints
      #|   INTEG-OK-31337; stand it in for now with a program that waits that
      #|   long and prints exactly that line. Report the line it prints.
      #|2. Report how many files are in agent_tool/bgjobs.
      #|3. Report the first line of docs/plans/shell-execution-model.md.
    ),
  )
  let seen : Array[Json] = []
  let finished = engine.wait_for(360_000, seen, event => {
    event is { "event": String("agent_finished"), .. }
  })
  let wall_s = (@env.now().reinterpret_as_int64() - started_ms) / 1000
  let backgrounded = seen.search_by(moved_to_background)
  // The marker inside a plain `mbtx` result means the slow program ran
  // (and blocked) in the foreground.
  let blocked_foreground = seen
    .iter()
    .any(event => {
      event
      is {
        "event": String("tool_result"),
        "tool_name": String("mbtx"),
        "content": String(content),
        ..
      } &&
      content.contains("INTEG-OK-31337") &&
      !content.contains("moved to the background")
    })
  // Any tool activity strictly between the job start and the marker retrieval
  // shows the wait was actually used for work.
  let retrieved_at = seen.search_by(event => {
    event
    is {
      "event": String("tool_result"),
      "tool_name": String("job_output"),
      "content": String(content),
      ..
    } &&
    content.contains("INTEG-OK-31337")
  })
  let overlapped = match (backgrounded, retrieved_at) {
    (Some(started), Some(retrieved)) if started < retrieved =>
      seen[started + 1:retrieved]
      .iter()
      .any(event => {
        event
        is { "event": String("tool_result"), "tool_name": String(name), .. } &&
        name != "job_output"
      })
    _ => false
  }
  let answer = match finished {
    Some({ "event": String("agent_finished"), "answer": String(answer), .. }) =>
      answer
    _ => ""
  }
  report("S1 automatically handed off the slow run", backgrounded is Some(_))
  report("S1 did not block the turn on the slow command", !blocked_foreground)
  report("S1 overlapped quick work with the running job", overlapped)
  report(
    "S1 answer carries the slow command's output",
    answer.contains("INTEG-OK-31337"),
  )
  println(
    "  INFO  S1 turn wall-clock: \{wall_s}s (serial floor is ~20s + quick work)",
  )
}

///|
/// S2: the user explicitly does not want to wait. Judgment under measurement:
/// fire the job and end the turn — do not hold the turn hostage for 45s.
async fn scenario_fire_and_forget(engine : Engine) -> Unit {
  println("== S2 fire-and-forget: user says do not wait ==")
  let started_ms = @env.now().reinterpret_as_int64()
  engine.prompt(
    (
      #|Kick off the long soak check. It runs about 45 seconds and then prints
      #|SOAK-DONE-555; stand it in for now with a program that waits that long
      #|and prints exactly that line.
      #|I do not need the result now and I don't want you to wait for it —
      #|just get it running, tell me how you started it and how I can check on
      #|it later, and you're done.
    ),
  )
  let seen : Array[Json] = []
  let finished = engine.wait_for(240_000, seen, event => {
    event is { "event": String("agent_finished"), .. }
  })
  let wall_s = (@env.now().reinterpret_as_int64() - started_ms) / 1000
  let backgrounded = seen.any(moved_to_background)
  report("S2 automatically handed off the slow run", backgrounded)
  report(
    "S2 finished well before the 45s job (did not block)",
    finished is Some(_) && wall_s < 35,
  )
  println("  INFO  S2 turn wall-clock: \{wall_s}s (job runs 45s)")
  // Bonus visibility: the completion should surface as an idle notice.
  let seen_idle : Array[Json] = []
  let idle_notice = engine.wait_for(90_000, seen_idle, event => {
    event is { "event": String("background_notice"), .. }
  })
  report(
    "S2 completion later surfaced as an idle notice",
    idle_notice is Some(_),
  )
}

///|
/// A tool result whose text says the engine moved the command to the
/// background — the automatic-handoff marker both scenarios look for.
fn moved_to_background(event : Json) -> Bool {
  event is { "event": String("tool_result"), "content": String(content), .. } &&
  content.contains("moved to the background")
}

///|
fn report(name : String, ok : Bool) -> Unit {
  let label = if ok { "YES " } else { "NO  " }
  println("  \{label}  \{name}")
}

///|
/// The engine under test: `openseek serve` through `moon run` (always the
/// freshly built binary), pinned environment (a developer's OPENSEEK_*
/// overrides or personal skills must not steer the measurement).
priv struct Engine {
  writer : @process.WriteToProcess
  events : @async.Queue[Json]
}

///|
async fn[G] Engine::spawn(group : @async.TaskGroup[G]) -> Engine {
  let (child_stdin, writer) = @process.write_to_process()
  let (reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  let parent = @env.get_env_vars()
  let child_env : Map[String, String] = Map([])
  for name in ["PATH", "HOME", "TMPDIR", "DEEPSEEK"] {
    if parent.get(name) is Some(value) {
      child_env[name] = value
    }
  }
  child_env["OPENSEEK_GLOBAL_SKILLS_DIR"] = "/nonexistent/openseek-eval-no-skills"
  let _proc = @process.spawn(
    group,
    "moon",
    ["run", "--target", "native", "cmd/openseek", "--", "serve"],
    inherit_env=false,
    extra_env=child_env,
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=child_stderr,
    no_wait=true,
  )
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    for ;; {
      if (stderr_reader.read_some(max_len=4096) catch { _ => None }) is None {
        break
      }
    }
  }
  let events : @async.Queue[Json] = Queue(kind=Unbounded)
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    @jsonl.each(reader, json => {
      ignore(events.try_put(json) catch { _ => false })
    })
    ignore(events.try_put({ "event": "__engine_eof" }) catch { _ => false })
  }
  { writer, events, }
}

///|
async fn Engine::prompt(self : Engine, text : String) -> Unit {
  let command : Json = { "command": "prompt", "text": text.to_json() }
  self.writer.write("\{command.stringify()}\n")
}

///|
async fn Engine::wait_for(
  self : Engine,
  timeout_ms : Int,
  seen : Array[Json],
  matches : (Json) -> Bool,
) -> Json? {
  let result = @async.with_timeout_opt(timeout_ms, () => {
    for ;; {
      let event = self.events.get()
      if event is { "event": String("__engine_eof"), .. } {
        break None
      }
      seen.push(event)
      // A failed or aborted turn is terminal for whatever we were waiting on:
      // stop now with the real cause in `seen` instead of burning the timeout.
      if event
        is {
          "event": String(
            "turn_failed"
            | "agent_aborted"
            | "max_steps_exhausted"
          ),
          ..
        } {
        break None
      }
      if matches(event) {
        break Some(event)
      }
    }
  })
  result.unwrap_or(None)
}
