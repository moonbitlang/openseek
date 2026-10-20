///|
/// The shared fixture with a conversation that has begun, so it has jobs to
/// list, and a workflow subagent running, so the background tasks card shows.
fn begun_model() -> Model {
  let model = test_model()
  {
    ..model,
    conversations: model.conversations.map(conv => {
      let workflows = @workflow.opened(
        [],
        id="wf-1",
        session=conv.session_id,
        first_child=1,
        child_count=1,
      )
      {
        ..conv,
        messages: [user_item("build it")],
        workflows: @workflow.child_opened(
          workflows,
          id="sr-1",
          kind="explore",
          label="map the code",
        ),
      }
    }),
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
  // Hiding the overview stops the listing and drops the reply in flight.
  let (_, hidden) = update(dispatch, ToggleOverview, shown)
  assert_true(hidden.jobs.watch is Unwatched)
  assert_false(hidden.jobs.listing)
  assert_true(hidden.jobs.epoch != shown.jobs.epoch)
  let (_, idle) = update(dispatch, Jobs(Poll), hidden)
  assert_false(idle.jobs.listing)
}

///|
test "the Jobs panel takes the listing over and the card's button hides it" {
  let dispatch = test_dispatch()
  let (_, shown) = update(dispatch, ToggleOverview, begun_model())
  guard shown.active_conversation() is Some(conv) else {
    fail("the fixture has a conversation on screen")
  }
  guard shown.overview_background(dispatch, conv) is Some(background) else {
    fail("a running subagent should show the background tasks card")
  }
  assert_eq(background.tasks.subagents, ["explore: map the code"])
  assert_false(background.jobs.shown)
  let (_, panel) = update(dispatch, JobsRequested, shown)
  assert_true(panel.jobs.watch is Panel)
  guard panel.overview_background(dispatch, conv) is Some(background) else {
    fail("the card stays while the subagent runs")
  }
  assert_true(background.jobs.shown)
  assert_false(background.workflows.shown)
  // Closing the panel hands the listing back to the overview on screen.
  let (_, closed) = update(dispatch, ToggleRightPanel, panel)
  assert_true(closed.jobs.watch is Summary)
  let (_, hidden) = update(dispatch, ToggleOverview, closed)
  assert_true(hidden.jobs.watch is Unwatched)
}
