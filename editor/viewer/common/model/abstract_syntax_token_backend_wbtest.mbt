///| Attached-view identity, aggregation, stabilization, and debounce evidence.

///|
priv struct ScheduledCallback {
  callback : () -> Unit
  active : Ref[Bool]
}

///|
fn deterministic_scheduler(
  delayed : Array[ScheduledCallback],
) -> TokenizationScheduler {
  TokenizationScheduler(
    idle=callback => {
      callback(TokenizationIdleDeadline(() => 0.0))
      @base_common.Disposable::from(() => ())
    },
    zero_timeout=callback => {
      callback()
      @base_common.Disposable::from(() => ())
    },
    delay=(_milliseconds, callback) => {
      let active = Ref(true)
      delayed.push({ callback, active, })
      @base_common.Disposable::from(() => active.val = false)
    },
    now=() => 0.0,
  )
}

///|
fn run_scheduled(task : ScheduledCallback) -> Unit {
  if task.active.val {
    (task.callback)()
  }
}

///|
test "AttachedViewState equality checks ranges before stabilization" {
  let ranges = [@base_common.LineRange(1, 3)]
  let a = AttachedViewState(ranges, false)
  let same = AttachedViewState([LineRange(1, 3)], false)
  let different_ranges = AttachedViewState([LineRange(1, 4)], false)
  let different_stability = AttachedViewState([LineRange(1, 3)], true)
  assert_true(a.equals(a))
  assert_true(a.equals(same))
  assert_false(a.equals(different_ranges))
  assert_false(a.equals(different_stability))
}

///|
test "AttachedViews preserves identity and emits committed and absent states" {
  let manager = AttachedViews()
  let events : Array[AttachedViewStateChange] = []
  manager.on_did_change_visible_ranges(event => events.push(event)) |> ignore
  let first = manager.attach_view()
  let second = manager.attach_view()
  first.set_visible_lines(
    [{ start_line_number: 3, end_line_number: 5, }],
    false,
  )
  let first_state = first.state_value.unwrap()
  assert_false(first_state.stabilized)
  assert_eq(first_state.visible_line_ranges.length(), 1)
  assert_eq(first_state.visible_line_ranges[0].start_line_number, 3)
  assert_eq(first_state.visible_line_ranges[0].end_line_number_exclusive, 6)
  second.set_visible_lines(
    [
      { start_line_number: 1, end_line_number: 2, },
      { start_line_number: 6, end_line_number: 7, },
    ],
    true,
  )
  assert_true(events[0].view.same(first))
  assert_true(events[1].view.same(second))
  let second_state = second.state_value.unwrap()
  assert_eq(second_state.visible_line_ranges.length(), 2)
  assert_eq(second_state.visible_line_ranges[0].start_line_number, 1)
  assert_eq(second_state.visible_line_ranges[1].start_line_number, 6)
  manager.detach_view(first)
  assert_true(events[2].view.same(first))
  assert_true(events[2].state is None)
  assert_true(first.state_value.unwrap().equals(first_state))
}

///|
test "AttachedViewHandler debounces unstable state and stable state cancels then refreshes" {
  let delayed : Array[ScheduledCallback] = []
  let scheduler = deterministic_scheduler(delayed)
  let mut refresh_count = 0
  let handler = AttachedViewHandler(() => refresh_count += 1, () => {
    Some(scheduler)
  })
  handler.handle_state_change(AttachedViewState([LineRange(1, 3)], false))
  assert_eq(delayed.length(), 1)
  assert_eq(refresh_count, 0)
  handler.handle_state_change(AttachedViewState([LineRange(2, 4)], false))
  assert_eq(delayed.length(), 2)
  run_scheduled(delayed[0])
  assert_eq(refresh_count, 0)
  run_scheduled(delayed[1])
  assert_eq(refresh_count, 1)
  handler.handle_state_change(AttachedViewState([LineRange(5, 7)], false))
  assert_eq(delayed.length(), 3)
  handler.handle_state_change(AttachedViewState([LineRange(5, 7)], true))
  assert_eq(refresh_count, 2)
  run_scheduled(delayed[2])
  assert_eq(refresh_count, 2)
  // Equal requested/computed ranges suppress a repeated stable refresh.
  handler.handle_state_change(AttachedViewState([LineRange(5, 7)], true))
  assert_eq(refresh_count, 2)
}
