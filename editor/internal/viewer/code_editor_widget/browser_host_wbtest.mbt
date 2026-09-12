// Exact browser-idle adapter coverage for pinned
// `base/common/async.ts:1536-1579` (BIA-001..023). Tests construct isolated
// realms so the process-global feature selection remains immutable.

///|
fn assert_idle_adapter_path(
  has_request_idle : Bool,
  has_cancel_idle : Bool,
  expects_native : Bool,
) -> Unit raise {
  let target = new_idle_target(has_request_idle, has_cancel_idle)
  let adapter = create_tokenization_idle_adapter_js(target)
  let cancel = run_tokenization_idle_adapter_js(
    adapter,
    _deadline => (),
    false,
    0.0,
  )
  if expects_native {
    assert_eq(idle_target_request_count(target), 1)
    assert_eq(idle_target_timeout_count(target), 0)
  } else {
    assert_eq(idle_target_request_count(target), 0)
    assert_eq(idle_target_timeout_count(target), 1)
    assert_eq(idle_target_timeout_delay(target, 0), 0)
  }
  cancel()
}

///|
test "BIA feature detection uses native idle only when both APIs are functions" {
  assert_idle_adapter_path(false, false, false)
  assert_idle_adapter_path(true, false, false)
  assert_idle_adapter_path(false, true, false)
  assert_idle_adapter_path(true, true, true)
}

///|
test "BIA adapter selects once and the global wrapper is asynchronous cancellable idle" {
  let target = new_idle_target(false, false)
  let adapter = create_tokenization_idle_adapter_js(target)
  idle_target_install_native_api(target)
  let local_cancel = run_tokenization_idle_adapter_js(
    adapter,
    _deadline => abort("once-selected fallback must be canceled"),
    false,
    0.0,
  )
  // Adding both native functions after construction cannot change the chosen
  // fallback implementation.
  assert_eq(idle_target_request_count(target), 0)
  assert_eq(idle_target_timeout_count(target), 1)
  local_cancel()
  idle_target_run_timeout(target, 0)

  let mut global_called = false
  let global_handle = schedule_tokenization_idle(_deadline => {
    global_called = true
  })
  assert_false(global_called)
  global_handle.dispose()
  global_handle.dispose()
}

///|
test "BIA native idle forwards absent and numeric timeout and cancels exact handle once" {
  let target = new_idle_target(true, true)
  let adapter = create_tokenization_idle_adapter_js(target)
  let delivered = Ref(0)
  let remaining = Ref(-1.0)
  let did_timeout = Ref(true)
  let absent = run_tokenization_idle_adapter_js(
    adapter,
    deadline => {
      delivered.val += 1
      remaining.val = browser_idle_deadline_time_remaining_js(deadline)
      did_timeout.val = browser_idle_deadline_did_timeout_js(deadline)
    },
    false,
    0.0,
  )
  assert_eq(idle_target_request_count(target), 1)
  assert_false(idle_target_request_had_options(target, 0))
  assert_eq(idle_target_request_handle(target, 0), 41)
  idle_target_run_request(target, 41, false, 7.0)
  assert_eq(delivered.val, 1)
  assert_eq(remaining.val, 7.0)
  assert_false(did_timeout.val)
  absent()
  absent()
  assert_eq(idle_target_cancel_count(target), 1)
  assert_eq(idle_target_canceled_handle(target, 0), 41)

  let present = run_tokenization_idle_adapter_js(
    adapter,
    _deadline => (),
    true,
    37.0,
  )
  assert_eq(idle_target_request_count(target), 2)
  assert_true(idle_target_request_had_options(target, 1))
  assert_eq(idle_target_request_timeout(target, 1), 37.0)
  assert_eq(idle_target_request_handle(target, 1), 42)
  present()
  present()
  assert_eq(idle_target_cancel_count(target), 2)
  assert_eq(idle_target_canceled_handle(target, 1), 42)
}

///|
test "BIA fallback schedules zero-timeout and freezes a plus-15ms deadline" {
  let target = new_idle_target(false, false)
  idle_target_set_now(target, 100.0)
  let adapter = create_tokenization_idle_adapter_js(target)
  let remaining : Array[Double] = []
  let did_timeout = Ref(false)
  let mut frozen = false
  let cancel = run_tokenization_idle_adapter_js(
    adapter,
    deadline => {
      did_timeout.val = browser_idle_deadline_did_timeout_js(deadline)
      frozen = browser_idle_deadline_is_frozen_js(deadline)
      remaining.push(browser_idle_deadline_time_remaining_js(deadline))
      idle_target_set_now(target, 114.0)
      remaining.push(browser_idle_deadline_time_remaining_js(deadline))
      idle_target_set_now(target, 115.0)
      remaining.push(browser_idle_deadline_time_remaining_js(deadline))
      idle_target_set_now(target, 116.0)
      remaining.push(browser_idle_deadline_time_remaining_js(deadline))
    },
    false,
    0.0,
  )
  assert_eq(idle_target_timeout_count(target), 1)
  assert_eq(idle_target_timeout_delay(target, 0), 0)
  assert_true(remaining.is_empty())
  idle_target_run_timeout(target, 0)
  assert_true(did_timeout.val)
  assert_true(frozen)
  assert_eq(remaining.length(), 4)
  assert_eq(remaining[0], 15.0)
  assert_eq(remaining[1], 1.0)
  assert_eq(remaining[2], 0.0)
  assert_eq(remaining[3], 0.0)
  cancel()
}

///|
test "BIA fallback cancellation is inert idempotent and leaves timeout callback harmless" {
  let target = new_idle_target(false, false)
  let adapter = create_tokenization_idle_adapter_js(target)
  let delivered = Ref(0)
  let cancel = run_tokenization_idle_adapter_js(
    adapter,
    _deadline => delivered.val += 1,
    false,
    0.0,
  )
  assert_eq(idle_target_timeout_count(target), 1)
  cancel()
  cancel()
  // The source does not clear the timer; its callback observes `disposed` and
  // returns before constructing the deadline or invoking the runner.
  assert_eq(idle_target_timeout_count(target), 1)
  idle_target_run_timeout(target, 0)
  assert_eq(delivered.val, 0)
}

///|
extern "js" fn browser_idle_deadline_did_timeout_js(
  deadline : BrowserIdleDeadline,
) -> Bool = "(deadline) => deadline.didTimeout"

///|
extern "js" fn browser_idle_deadline_is_frozen_js(
  deadline : BrowserIdleDeadline,
) -> Bool = "(deadline) => Object.isFrozen(deadline)"

///|
extern "js" fn new_idle_target(
  has_request_idle : Bool,
  has_cancel_idle : Bool,
) -> TokenizationIdleTarget =
  #| (hasRequestIdle, hasCancelIdle) => {
  #|   const state = {
  #|     now: 0,
  #|     nextHandle: 41,
  #|     requests: [],
  #|     cancellations: [],
  #|     timeouts: [],
  #|   };
  #|   const target = {
  #|     Date: { now: () => state.now },
  #|     setTimeout: (callback, delay) => {
  #|       state.timeouts.push({ callback, delay });
  #|       return state.timeouts.length;
  #|     },
  #|     __idleState: state,
  #|   };
  #|   const installRequest = () => {
  #|     target.requestIdleCallback = (callback, options) => {
  #|       const handle = state.nextHandle++;
  #|       state.requests.push({ callback, options, handle });
  #|       return handle;
  #|     };
  #|   };
  #|   const installCancel = () => {
  #|     target.cancelIdleCallback = (handle) => {
  #|       state.cancellations.push(handle);
  #|     };
  #|   };
  #|   target.__installNativeApi = () => {
  #|     installRequest();
  #|     installCancel();
  #|   };
  #|   if (hasRequestIdle) installRequest();
  #|   if (hasCancelIdle) installCancel();
  #|   return target;
  #| }

///|
extern "js" fn idle_target_install_native_api(
  target : TokenizationIdleTarget,
) -> Unit = "(target) => target.__installNativeApi()"

///|
extern "js" fn idle_target_set_now(
  target : TokenizationIdleTarget,
  now : Double,
) -> Unit = "(target, now) => { target.__idleState.now = now; }"

///|
extern "js" fn idle_target_request_count(
  target : TokenizationIdleTarget,
) -> Int = "(target) => target.__idleState.requests.length"

///|
extern "js" fn idle_target_request_handle(
  target : TokenizationIdleTarget,
  index : Int,
) -> Int = "(target, index) => target.__idleState.requests[index].handle"

///|
extern "js" fn idle_target_request_had_options(
  target : TokenizationIdleTarget,
  index : Int,
) -> Bool = "(target, index) => target.__idleState.requests[index].options !== undefined"

///|
extern "js" fn idle_target_request_timeout(
  target : TokenizationIdleTarget,
  index : Int,
) -> Double = "(target, index) => target.__idleState.requests[index].options.timeout"

///|
extern "js" fn idle_target_run_request(
  target : TokenizationIdleTarget,
  handle : Int,
  did_timeout : Bool,
  remaining : Double,
) -> Unit =
  #| (target, handle, didTimeout, remaining) => {
  #|   const request = target.__idleState.requests.find(
  #|     (candidate) => candidate.handle === handle,
  #|   );
  #|   if (!request) throw new Error(`missing idle request ${handle}`);
  #|   request.callback({ didTimeout, timeRemaining: () => remaining });
  #| }

///|
extern "js" fn idle_target_cancel_count(target : TokenizationIdleTarget) -> Int = "(target) => target.__idleState.cancellations.length"

///|
extern "js" fn idle_target_canceled_handle(
  target : TokenizationIdleTarget,
  index : Int,
) -> Int = "(target, index) => target.__idleState.cancellations[index]"

///|
extern "js" fn idle_target_timeout_count(
  target : TokenizationIdleTarget,
) -> Int = "(target) => target.__idleState.timeouts.length"

///|
extern "js" fn idle_target_timeout_delay(
  target : TokenizationIdleTarget,
  index : Int,
) -> Int = "(target, index) => target.__idleState.timeouts[index].delay"

///|
extern "js" fn idle_target_run_timeout(
  target : TokenizationIdleTarget,
  index : Int,
) -> Unit = "(target, index) => target.__idleState.timeouts[index].callback()"
