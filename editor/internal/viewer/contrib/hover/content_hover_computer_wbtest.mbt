///|
fn computer_test_model() -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/hover-test.mbt",
    ),
    "hover-test.mbt",
    "moonbit",
    7,
    "rev-7",
    (
      #|fn main {
      #|  value
      #|}
      #|
    ),
  )
}

///|
async test "content hover computer separates sync markers from async markdown" {
  let languages = @languages.Languages()
  let markers = @markers.MarkerService()
  let marker_decorations = @markers.MarkerDecorationsService(
    markers.marker_service_handle(),
  )
  let model = computer_test_model()
  marker_decorations.on_model_added(model)
  markers.set_diagnostics("diagnostics:0", model.uri, [
    {
      range: Range(2, 3, 2, 8),
      severity: Warning,
      message: "marker hover",
      tags: None,
    },
  ])
  languages.register_hover_provider(LanguageId("moonbit"), ComputerHoverProvider::{
  })
  |> ignore
  let services : HoverParticipantServices = {
    languages: languages.language_handle(@log.LogService().log_handle()),
    marker_decorations: marker_decorations.marker_decorations_handle(),
  }
  let computer = ContentHoverComputer(services)
  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 8),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let sync_hover = computer.compute_sync(model, anchor)
  match sync_hover {
    Some(hover) => {
      assert_eq(hover.parts.length(), 1)
      assert_true(hover.parts[0] is MarkerHover(_))
    }
    None => fail("expected marker hover")
  }
  let async_hover = computer.compute_async(model, anchor)
  match async_hover {
    Some(hover) => {
      assert_eq(hover.parts.length(), 1)
      assert_true(hover.parts[0] is MarkdownHover(_))
    }
    None => fail("expected markdown hover")
  }
}

///|
priv struct ComputerHoverProvider {}

///|
impl @language.HoverProvider for ComputerHoverProvider with fn provide_hover(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  Some({
    range: model.snapshot.range_of(OffsetRange(offset, offset + 1)),
    contents: [PlainText("provider hover")],
  })
}

///|
priv struct RecordingHoverProvider {
  calls : Ref[Int]
  seen_token : Ref[@language.CancellationToken?]
}

///|
impl @language.HoverProvider for RecordingHoverProvider with fn provide_hover(
  self,
  model,
  position,
  token,
) {
  self.calls.val += 1
  self.seen_token.val = Some(token)
  let offset = model.get_offset_at(position)
  Some({
    range: model.snapshot.range_of(OffsetRange(offset, offset + 1)),
    contents: [PlainText("recorded provider hover")],
  })
}

///|
fn computer_services_with_languages(
  languages : @languages.Languages,
) -> HoverParticipantServices {
  let markers = @markers.MarkerService()
  let marker_decorations = @markers.MarkerDecorationsService(
    markers.marker_service_handle(),
  )
  {
    languages: languages.language_handle(@log.LogService().log_handle()),
    marker_decorations: marker_decorations.marker_decorations_handle(),
  }
}

///|
async test "caller cancellation token reaches the language provider unchanged" {
  let languages = @languages.Languages()
  let calls = Ref(0)
  let seen_token : Ref[@language.CancellationToken?] = Ref(None)
  languages.register_hover_provider(LanguageId("moonbit"), RecordingHoverProvider::{
    calls,
    seen_token,
  })
  |> ignore
  let computer = ContentHoverComputer(
    computer_services_with_languages(languages),
  )
  let model = computer_test_model()
  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let token = @language.CancellationToken()
  assert_true(computer.compute_async(model, anchor, token~) is Some(_))
  assert_eq(calls.val, 1)
  match seen_token.val {
    Some(provider_token) => {
      assert_true(physical_equal(provider_token, token))
      token.cancel()
      // Cancellation through the caller's value is observable through the
      // exact token value retained by the provider.
      assert_true(provider_token.is_cancellation_requested())
    }
    None => fail("expected provider token")
  }
}

///|
async test "pre-canceled async computation never launches a participant provider" {
  let languages = @languages.Languages()
  let calls = Ref(0)
  let seen_token : Ref[@language.CancellationToken?] = Ref(None)
  languages.register_hover_provider(LanguageId("moonbit"), RecordingHoverProvider::{
    calls,
    seen_token,
  })
  |> ignore
  let computer = ContentHoverComputer(
    computer_services_with_languages(languages),
  )
  let model = computer_test_model()
  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let token = @language.CancellationToken()
  token.cancel()
  assert_true(computer.compute_async(model, anchor, token~) is None)
  assert_eq(calls.val, 0)
  assert_true(seen_token.val is None)
}

///|
fn first_plain_text(parts : Array[HoverPart]) -> String {
  guard parts.get(0) is Some(MarkdownHover(contents~, ..)) else { return "" }
  match contents.get(0) {
    Some(PlainText(text)) => text
    _ => ""
  }
}

///|
fn async_test_anchor() -> HoverAnchor {
  HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
}

///|
/// Starts every participant task before waiting for the group. The per-
/// participant semaphores below control completion independently, so the test
/// can observe one emitted result while its sibling is still suspended.
async fn run_hover_test_tasks_concurrently(
  tasks : Array[async () -> Unit],
) -> Unit {
  @async.with_task_group() <| group => {
    for task in tasks {
      group.spawn_bg(task)
    }
  }
}

///|
priv struct SuspendedHoverParticipant {
  ordinal_value : Int
  text : String
  started : @async.Semaphore
  release_gate : @async.Semaphore
  finished : Ref[Bool]
}

///|
fn SuspendedHoverParticipant::hover_participant_handle(
  self : SuspendedHoverParticipant,
) -> HoverParticipantHandle {
  HoverParticipantHandle(self.ordinal_value, _ctx => [], compute_async=(
    ctx,
    _token,
  ) => {
    self.started.release()
    self.release_gate.acquire() catch {
      _ => return []
    }
    self.finished.val = true
    [
      MarkdownHover(
        range=ctx.anchor.range(),
        contents=[PlainText(self.text)],
        ordinal=self.ordinal_value,
      ),
    ]
  })
}

///|
async test "async-each skips participants without an async callback" {
  let computer : ContentHoverComputer = {
    participants: [HoverParticipantHandle(10, _ctx => [])],
  }
  let mut runner_called = false
  let emitted = Ref(0)
  computer.compute_async_each(
    computer_test_model(),
    async_test_anchor(),
    run_tasks=tasks => {
      runner_called = true
      assert_true(tasks.is_empty())
    },
    emit=_parts => emitted.val += 1,
  )
  assert_true(runner_called)
  assert_eq(emitted.val, 0)
}

///|
async test "async-each emits B while A remains suspended then preserves B-to-A arrival order" {
  let started = @async.Semaphore(2, initial_value=0)
  let release_a = @async.Semaphore(1, initial_value=0)
  let release_b = @async.Semaphore(1, initial_value=0)
  let emitted_signal = @async.Semaphore(2, initial_value=0)
  let finished_a = Ref(false)
  let finished_b = Ref(false)
  let computer : ContentHoverComputer = {
    participants: [
      SuspendedHoverParticipant::{
        ordinal_value: 10,
        text: "a",
        started,
        release_gate: release_a,
        finished: finished_a,
      }.hover_participant_handle(),
      SuspendedHoverParticipant::{
        ordinal_value: 20,
        text: "b",
        started,
        release_gate: release_b,
        finished: finished_b,
      }.hover_participant_handle(),
    ],
  }
  let emitted : Array[String] = []
  @async.with_task_group() <| group => {
    let request = group.spawn(() => {
      computer.compute_async_each(
        computer_test_model(),
        async_test_anchor(),
        run_tasks=run_hover_test_tasks_concurrently,
        emit=parts => {
          emitted.push(first_plain_text(parts))
          emitted_signal.release()
        },
      )
    })

    // Both producers have started and are suspended on independent gates.
    started.acquire()
    started.acquire()
    assert_false(finished_a.val)
    assert_false(finished_b.val)

    // B completes first. Its partial result is observable while A remains
    // blocked, proving emission does not wait for the whole participant set.
    release_b.release()
    emitted_signal.acquire()
    assert_true(finished_b.val)
    assert_false(finished_a.val)
    assert_eq(emitted.join(","), "b")

    release_a.release()
    emitted_signal.acquire()
    request.wait()
    assert_true(finished_a.val)
    assert_eq(emitted.join(","), "b,a")
  }
}
