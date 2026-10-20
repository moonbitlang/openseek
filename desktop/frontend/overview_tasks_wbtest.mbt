///|
/// The shared fixture with a conversation that has begun, so it has jobs to
/// list.
fn begun_model() -> Model {
  let model = test_model()
  {
    ..model,
    conversations: model.conversations.map(conv => {
      ..conv,
      messages: [user_item("build it")],
    }),
  }
}

///|
fn running_job(command : String) -> @protocol.JobView {
  {
    job: {
      generation: "runtime",
      id: "bg-1",
      revision: 1,
      command,
      description: None,
      cwd: None,
      state: Running,
      started_at_ms: 0L,
      backgrounded_at_ms: 0L,
      finished_at_ms: None,
      last_output_at_ms: None,
      output_file: None,
      output_persistent: false,
      output_bytes: 0L,
      output_chars: 0,
      output_truncated: false,
      invalid_utf8: false,
      output_error: None,
      persistence_error: None,
      cleanup_error: None,
      data: None,
      subagent: None,
    },
    output_path: None,
    controllable: true,
    error: None,
  }
}

///|
test "the overview lists the conversation's jobs and stops when hidden" {
  let dispatch = test_dispatch()
  let model = begun_model()
  // Neither the overview nor the Jobs panel is on screen: nothing is asked.
  assert_true(model.jobs.watch is Unwatched)
  let (_, shown) = update(dispatch, ToggleOverview, model)
  assert_true(shown.jobs.watch is Summary)
  assert_true(shown.jobs.listing)
  guard shown.active_conversation() is Some(conv) else {
    fail("the fixture has a conversation on screen")
  }
  assert_true(shown.overview_background(dispatch, conv) is None)
  // The listing's reply is what the card shows.
  let (_, listed) = update(
    dispatch,
    Jobs(
      Listed(
        shown.jobs.epoch,
        0,
        Ok({
          jobs: [running_job("npm run dev")],
          next_offset: None,
          errors: [],
          selected: None,
        }),
      ),
    ),
    shown,
  )
  guard listed.overview_background(dispatch, conv) is Some(background) else {
    fail("a running job should show the background tasks card")
  }
  assert_eq(background.tasks.jobs.map(job => job.command), ["npm run dev"])
  // The summary reads no output; the job was selected for the panel only.
  assert_false(listed.jobs.reading)
  // Hiding the overview stops the listing and drops the reply in flight.
  let (_, polled) = update(dispatch, Jobs(Poll), listed)
  assert_true(polled.jobs.listing)
  let (_, hidden) = update(dispatch, ToggleOverview, polled)
  assert_true(hidden.jobs.watch is Unwatched)
  assert_false(hidden.jobs.listing)
  assert_true(hidden.jobs.epoch != polled.jobs.epoch)
  let (_, idle) = update(dispatch, Jobs(Poll), hidden)
  assert_false(idle.jobs.listing)
}

///|
test "the Jobs panel takes the listing over from the overview" {
  let dispatch = test_dispatch()
  let (_, shown) = update(dispatch, ToggleOverview, begun_model())
  assert_true(shown.jobs.watch is Summary)
  let (_, panel) = update(dispatch, JobsRequested, shown)
  assert_true(panel.jobs.watch is Panel)
  // Closing the panel hands the listing back to the overview on screen.
  let (_, closed) = update(dispatch, ToggleRightPanel, panel)
  assert_false(closed.right_panel_open)
  assert_true(closed.jobs.watch is Summary)
  let (_, hidden) = update(dispatch, ToggleOverview, closed)
  assert_true(hidden.jobs.watch is Unwatched)
}
