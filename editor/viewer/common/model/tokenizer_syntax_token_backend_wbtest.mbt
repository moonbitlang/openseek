///| Concrete backend passive-read, reset, visible refresh, lifecycle, and cancellation evidence.

///|
priv struct BackendHarness {
  model_state : TokenizationModelState
  attached : Ref[Int]
  scheduler : Ref[TokenizationScheduler?]
  disposing : Ref[Bool]
  errors : Array[String]
}

///|
fn backend_harness(
  lines : Array[String],
  too_large? : Bool = false,
) -> BackendHarness {
  let attached = Ref(0)
  let scheduler : Ref[TokenizationScheduler?] = Ref(None)
  let disposing = Ref(false)
  let errors : Array[String] = []
  let model_state = test_tokenization_model_state(
    lines,
    "backend-test",
    attached,
    too_large,
    disposing,
    scheduler,
    message => errors.push(message),
  )
  { model_state, attached, scheduler, disposing, errors, }
}

///|
priv struct IdleTask {
  callback : (TokenizationIdleDeadline) -> Unit
  active : Ref[Bool]
}

///|
priv struct BackendSchedulerHarness {
  scheduler : TokenizationScheduler
  idle : Array[IdleTask]
}

///|
fn backend_scheduler_harness() -> BackendSchedulerHarness {
  let idle : Array[IdleTask] = []
  let now = Ref(0.0)
  let scheduler = TokenizationScheduler(
    idle=callback => {
      let active = Ref(true)
      idle.push({ callback, active, })
      @base_common.Disposable::from(() => active.val = false)
    },
    zero_timeout=_callback => @base_common.Disposable::from(() => ()),
    delay=(_ms, _callback) => @base_common.Disposable::from(() => ()),
    now=() => now.val,
  )
  { scheduler, idle, }
}

///|
fn run_idle(task : IdleTask, remaining? : Double = 0.0) -> Unit {
  if task.active.val {
    (task.callback)(TokenizationIdleDeadline(() => remaining))
  }
}

///|
test "passive reads never invoke support; stable attached ranges store exact ranges" {
  let harness = backend_harness(["one", "two"])
  let attached_views = AttachedViews()
  let calls : Array[String] = []
  let initial_calls = Ref(0)
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    attached_views,
    _ => Some(logging_support(calls, initial_calls)),
  )
  let events : Array[ModelTokensChangedEvent] = []
  backend.on_did_change_tokens(event => events.push(event)) |> ignore
  assert_eq(initial_calls.val, 2)
  assert_eq(backend.get_line_tokens(1).get_count(), 1)
  assert_eq(backend.get_line_tokens(2).get_count(), 1)
  assert_eq(calls.length(), 0)
  let view = attached_views.attach_view()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 2, }], true)
  assert_eq(calls.length(), 2)
  assert_eq(events.length(), 1)
  assert_eq(events[0].ranges[0].from_line_number, 1)
  assert_eq(events[0].ranges[0].to_line_number, 2)
}

///|
/// A visible model range can be a single line ending exactly at the
/// tokenization frontier (the first line of a file whose second line is hidden
/// by a rich replacement). It must be tokenized by the stable refresh instead
/// of waiting for the background worker's idle turn.
test "stable single-line range at the frontier is tokenized synchronously" {
  let harness = backend_harness(["one", "two"])
  let attached_views = AttachedViews()
  let calls : Array[String] = []
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    attached_views,
    _ => Some(logging_support(calls, Ref(0))),
  )
  let events : Array[ModelTokensChangedEvent] = []
  backend.on_did_change_tokens(event => events.push(event)) |> ignore
  let view = attached_views.attach_view()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 1, }], true)
  assert_eq(calls.length(), 1)
  assert_eq(events.length(), 1)
  assert_eq(events[0].ranges[0].from_line_number, 1)
  assert_eq(events[0].ranges[0].to_line_number, 1)
  // The same stable range is now accurate and refreshes nothing.
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 1, }], true)
  assert_eq(calls.length(), 1)
  assert_eq(events.length(), 1)
}

///|
test "too-large and missing support stay passive defaults and schedule nothing" {
  let harness = backend_harness(["one"], too_large=true)
  let resolves = Ref(0)
  let attached_views = AttachedViews()
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    attached_views,
    _ => {
      resolves.val += 1
      Some(logging_support([], Ref(0)))
    },
  )
  assert_eq(resolves.val, 0)
  let view = attached_views.attach_view()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 1, }], true)
  assert_eq(resolves.val, 0)
  assert_eq(backend.get_line_tokens(1).get_count(), 1)
}

///|
test "stable attached ranges refresh synchronously without a scheduler" {
  let harness = backend_harness(["one", "two", "three"])
  let attached_views = AttachedViews()
  let calls : Array[String] = []
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    attached_views,
    _ => Some(logging_support(calls, Ref(0))),
  )
  let handle = attached_views.attach_view()
  handle.set_visible_lines(
    [{ start_line_number: 1, end_line_number: 2, }],
    true,
  )
  assert_eq(calls.length(), 2)
  assert_eq(backend.get_line_tokens(1).get_line_content(), "one")
}

///|
test "scheduler None enqueues nothing; late scheduler wakes once and stale generation is inert" {
  let harness = backend_harness(["one", "two"])
  let calls : Array[String] = []
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    AttachedViews(),
    _ => Some(logging_support(calls, Ref(0))),
  )
  harness.attached.val = 1
  backend.handle_did_change_attached()
  assert_eq(calls.length(), 0)
  let scheduler = backend_scheduler_harness()
  harness.scheduler.val = Some(scheduler.scheduler)
  backend.handle_did_change_attached()
  assert_eq(scheduler.idle.length(), 1)
  let old_idle = scheduler.idle[0]
  harness.attached.val = 0
  backend.handle_did_change_attached()
  assert_false(old_idle.active.val)
  harness.attached.val = 1
  backend.handle_did_change_attached()
  assert_eq(scheduler.idle.length(), 2)
  // Simulate a hostile host invoking an already-cancelled old callback.
  (old_idle.callback)(TokenizationIdleDeadline(() => 0.0))
  assert_eq(calls.length(), 0)
  run_idle(scheduler.idle[1])
  assert_eq(calls.length(), 2)
}

///|
test "disposing guard drops token events from reset and visible refresh" {
  let harness = backend_harness(["one"])
  let attached_views = AttachedViews()
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    attached_views,
    _ => Some(logging_support([], Ref(0))),
  )
  let token_events = Ref(0)
  backend.on_did_change_tokens(_ => token_events.val += 1) |> ignore
  harness.disposing.val = true
  backend.reset_tokenization()
  let view = attached_views.attach_view()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 1, }], true)
  assert_eq(token_events.val, 0)
}

///|
priv suberror BackendInitialStateError {
  InitialStateFailure
}

///|
test "failing initial state reports and disables support for the reset" {
  let harness = backend_harness(["one"])
  let failing = InternalTokenizationSupportAdapter(
    initial_state=() => raise BackendInitialStateError::InitialStateFailure,
    tokenize_encoded=(_text, _has_eol, state) => {
      tokens: [0, tag_to_metadata(Plain)],
      end_state: state,
    },
  )
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    AttachedViews(),
    _ => Some(failing),
  )
  assert_eq(harness.errors.length(), 1)
  assert_eq(backend.get_line_tokens(1).get_count(), 1)
}

///|
test "refreshRange preserves asymmetric clamp and reversed no-work branches" {
  let harness = backend_harness(["one", "two", "three"])
  let calls : Array[String] = []
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    harness.model_state,
    AttachedViews(),
    _ => Some(logging_support(calls, Ref(0))),
  )
  backend.refresh_range(-10, 99)
  assert_eq(calls.length(), 3)
  calls.clear()
  backend.reset_tokenization(fire_token_change_event=false)
  backend.refresh_range(3, 1)
  assert_true(calls.is_empty())
  backend.refresh_range(99, 99)
  assert_eq(calls.length(), 1)
  assert_true(calls[0].has_prefix("three:true:"))
}
