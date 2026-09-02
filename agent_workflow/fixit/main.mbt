///|
/// The first READ→WRITE workflow: a scout researches one small, concrete
/// documentation defect, then a confined WORKER slice applies the fix in
/// its own git worktree — captured from git evidence onto a branch. The
/// demo prints the evidence and then DISCARDS the slice so it stays
/// rerunnable; swap the discard for `integrate_slice` to keep the fix.
///
///   moon run agent_workflow/fixit --target native     (from the repo root)
///
/// Needs `openseek` on PATH, a provider key in the environment, and a
/// CLEAN git tree (workers fork HEAD).
async fn main raise {
  let wf = @workflow.Workflow(
    runner=@agent_workflow.openseek_runner(
      exe="openseek",
      workspace_root=".",
      deadline_ms=600_000,
    ),
    journal=@workflow.Journal::load("fixit.jsonl"),
  )

  // ---- Phase 1: the scout finds something worth fixing ----
  wf.phase("Scout")
  let finding = wf.agent(
    "Find ONE small, uncontroversial documentation defect — a typo, a stale sentence, or a wrong identifier — in the markdown or doc comments of workflow/ or agent_workflow/. Reply with: the file path, the EXACT current text, and the corrected text. Pick something a one-line edit fixes.",
    kind="explore",
    max_steps=20,
    label="scout:defect",
  ) catch {
    error => {
      println("scout failed: \{error}")
      return
    }
  }
  let brief = match finding {
    { "answer": String(text), .. } => text
    other => other.stringify()
  }
  println("── scout found:\n\{clip(brief, 500)}\n")

  // ---- Phase 2: a confined worker applies it ----
  // The worker's task EMBEDS the scout's finding: edit the scout's
  // prompt later and replay re-runs both; edit nothing and both replay.
  wf.phase("Fix")
  match
    @agent_workflow.try_worker(
      wf,
      name="fixit",
      task="Apply EXACTLY this one documentation correction and nothing else: \{clip(brief, 1500)}",
      allowed_paths=["workflow/", "agent_workflow/"],
      max_steps=40,
    ) {
    Ok(outcome) => {
      println("── worker outcome:")
      if outcome is { "branch": String(branch), "state": String(state), .. } {
        println("   state \{state}, branch \{branch}")
      }
      if outcome is { "evidence": Array(evidence), .. } {
        for line in evidence {
          println("   \{line.stringify()}")
        }
      }
      // Keep the demo rerunnable: drop the slice (the branch and its
      // registry entry). To LAND the fix instead:
      //   @agent_workflow.integrate_slice(workspace_root=".", name="fixit")
      match
        @agent_workflow.discard_slice(workspace_root=".", name="fixit") {
        Ok(_) => println("   slice discarded — rerun-safe demo")
        Err(reason) => println("   discard: \{reason}")
      }
    }
    Err(error) => println("── worker failed: \{error}")
  }
  println(
    "\n\{wf.calls_made()} live, \{wf.calls_replayed()} replayed, \{wf.tokens_spent()} fresh tokens",
  )
}

///|
fn clip(text : String, limit : Int) -> String {
  let out = StringBuilder()
  let mut count = 0
  for ch in text {
    if count >= limit {
      break
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string()
}
