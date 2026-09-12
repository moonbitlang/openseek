// Ported from `vscode/src/vs/base/test/common/cancellation.test.ts` in the
// checked-in vscode source. The CancellationToken suite's
// source test names are preserved verbatim; CancellationTokenPool is explicitly
// deferred by the approved inventory.
//
// SKIPPED (DEFERRED CTS-042..055): "empty pool token is not cancelled",
// "pool token cancels when all tokens are cancelled", "pool token fires
// cancellation event when all tokens are cancelled", "adding already cancelled
// token counts immediately", "adding single already cancelled token cancels
// pool immediately", "adding token after pool is done has no effect", "single
// token pool behaviour", and "pool with only cancelled tokens".

///|
struct ScheduledCancellation {
  callback : () -> Unit
  active : Ref[Bool]
}

///|
fn manual_cancellation_scheduler(
  scheduled : Array[ScheduledCancellation],
) -> (() -> Unit) -> @base_common.Disposable {
  callback => {
    let active = Ref(true)
    scheduled.push({ callback, active, })
    @base_common.Disposable::from(() => active.val = false)
  }
}

///|
fn flush_cancellations(scheduled : Array[ScheduledCancellation]) -> Unit {
  let pending = scheduled.copy()
  scheduled.clear()
  for item in pending {
    if item.active.val {
      item.active.val = false
      (item.callback)()
    }
  }
}

///|
test "None" {
  let first = CancellationToken::none()
  let second = CancellationToken::none()
  assert_false(first.is_cancellation_requested())
  assert_true(physical_equal(first, second))
  let count = Ref(0)
  first.on_cancellation_requested(() => count.val += 1).dispose()
  assert_eq(count.val, 0)
}

///|
test "cancel before token" {
  let scheduled : Array[ScheduledCancellation] = []
  let source = @language.CancellationTokenSource(
    schedule=manual_cancellation_scheduler(scheduled),
  )
  assert_false(source.token().is_cancellation_requested())
  source.cancel()
  assert_true(source.token().is_cancellation_requested())
  let count = Ref(0)
  source.token().on_cancellation_requested(() => count.val += 1) |> ignore
  assert_eq(count.val, 0)
  assert_eq(scheduled.length(), 1)
  flush_cancellations(scheduled)
  assert_eq(count.val, 1)
}

///|
test "cancel before first token read keeps shortcut scheduling" {
  let scheduled : Array[ScheduledCancellation] = []
  let source = @language.CancellationTokenSource(
    schedule=manual_cancellation_scheduler(scheduled),
  )
  source.cancel()
  let token = source.token()
  assert_true(token.is_cancellation_requested())
  assert_true(physical_equal(token, source.token()))
  let count = Ref(0)
  let subscription = token.on_cancellation_requested(() => count.val += 1)
  assert_eq(count.val, 0)
  assert_eq(scheduled.length(), 1)
  subscription.dispose()
  flush_cancellations(scheduled)
  assert_eq(count.val, 0)
}

///|
test "cancel happens only once" {
  let source = @language.CancellationTokenSource()
  let token = source.token()
  assert_false(token.is_cancellation_requested())
  let mut cancel_count = 0
  let mut observed_cancelled = false
  token.on_cancellation_requested(() => {
    observed_cancelled = token.is_cancellation_requested()
    cancel_count += 1
  })
  |> ignore
  source.cancel()
  source.cancel()
  assert_eq(cancel_count, 1)
  assert_true(observed_cancelled)
}

///|
test "cancel calls all listeners" {
  let source = @language.CancellationTokenSource()
  let order : Array[Int] = []
  let subscriptions : Array[@base_common.Disposable] = []
  source
  .token()
  .on_cancellation_requested(() => order.push(1), disposables=subscriptions)
  |> ignore
  source
  .token()
  .on_cancellation_requested(() => order.push(2), disposables=subscriptions)
  |> ignore
  source
  .token()
  .on_cancellation_requested(() => order.push(3), disposables=subscriptions)
  |> ignore
  source.cancel()
  assert_eq(subscriptions.length(), 3)
  assert_eq(order.length(), 3)
  assert_eq(order[0], 1)
  assert_eq(order[1], 2)
  assert_eq(order[2], 3)
}

///|
test "token stays the same" {
  let source = @language.CancellationTokenSource()
  let token = source.token()
  assert_true(physical_equal(token, source.token()))
  source.cancel()
  assert_true(physical_equal(token, source.token()))
  source.cancel()
  assert_true(physical_equal(token, source.token()))

  let canceled_before_read = @language.CancellationTokenSource()
  canceled_before_read.cancel()
  let canceled = canceled_before_read.token()
  assert_true(physical_equal(canceled, canceled_before_read.token()))
  assert_true(
    physical_equal(
      CancellationToken::cancelled(),
      CancellationToken::cancelled(),
    ),
  )
}

///|
test "dispose calls no listeners" {
  let source = @language.CancellationTokenSource()
  let count = Ref(0)
  source.token().on_cancellation_requested(() => count.val += 1) |> ignore
  source.dispose()
  source.cancel()
  assert_eq(count.val, 0)
}

///|
test "dispose calls no listeners (unless told to cancel)" {
  let source = @language.CancellationTokenSource()
  let count = Ref(0)
  source.token().on_cancellation_requested(() => count.val += 1) |> ignore
  source.dispose(cancel=true)
  assert_eq(count.val, 1)
}

///|
test "dispose with cancellation before first token read stays cancelled" {
  let scheduled : Array[ScheduledCancellation] = []
  let source = @language.CancellationTokenSource(
    schedule=manual_cancellation_scheduler(scheduled),
  )
  source.dispose(cancel=true)
  let token = source.token()
  assert_true(token.is_cancellation_requested())
  let count = Ref(0)
  token.on_cancellation_requested(() => count.val += 1) |> ignore
  assert_eq(count.val, 0)
  flush_cancellations(scheduled)
  assert_eq(count.val, 1)
}

///|
test "dispose does not cancel" {
  let source = @language.CancellationTokenSource()
  source.dispose()
  assert_false(source.token().is_cancellation_requested())
  source.cancel()
  assert_false(source.token().is_cancellation_requested())
}

///|
test "parent cancels child" {
  let parent = @language.CancellationTokenSource()
  let child = @language.CancellationTokenSource(parent=parent.token())
  let count = Ref(0)
  child.token().on_cancellation_requested(() => count.val += 1) |> ignore
  parent.cancel()
  assert_eq(count.val, 1)
  assert_true(child.token().is_cancellation_requested())
  assert_true(parent.token().is_cancellation_requested())
  child.dispose()
  parent.dispose()
}

///|
test "late listener disposal suppresses scheduled delivery" {
  let scheduled : Array[ScheduledCancellation] = []
  let source = @language.CancellationTokenSource(
    schedule=manual_cancellation_scheduler(scheduled),
  )
  let token = source.token()
  source.cancel()
  let count = Ref(0)
  let subscription = token.on_cancellation_requested(() => count.val += 1)
  assert_eq(scheduled.length(), 1)
  subscription.dispose()
  flush_cancellations(scheduled)
  assert_eq(count.val, 0)
}

///|
test "listener closure captures context and bucket can dispose subscriptions" {
  let source = @language.CancellationTokenSource()
  let context = Ref("context:")
  let subscriptions : Array[@base_common.Disposable] = []
  source
  .token()
  .on_cancellation_requested(
    () => context.val = "\{context.val}cancelled",
    disposables=subscriptions,
  )
  |> ignore
  for subscription in subscriptions {
    subscription.dispose()
  }
  source.cancel()
  assert_eq(context.val, "context:")
}

///|
test "repeated dispose is harmless and detaches the parent" {
  let parent = @language.CancellationTokenSource()
  let child = @language.CancellationTokenSource(parent=parent.token())
  let count = Ref(0)
  child.token().on_cancellation_requested(() => count.val += 1) |> ignore
  child.dispose()
  child.dispose()
  parent.cancel()
  assert_eq(count.val, 0)
  assert_false(child.token().is_cancellation_requested())
  parent.dispose()
  parent.dispose()
}

///|
test "compatibility token remains directly cancellable" {
  let token = CancellationToken::CancellationToken()
  let count = Ref(0)
  token.on_cancellation_requested(() => count.val += 1) |> ignore
  token.cancel()
  token.cancel()
  assert_true(token.is_cancellation_requested())
  assert_eq(count.val, 1)
}

///|
test "source token cannot bypass its cancellation owner" {
  let source = @language.CancellationTokenSource()
  let token = source.token()
  token.cancel()
  assert_false(token.is_cancellation_requested())
  source.cancel()
  assert_true(token.is_cancellation_requested())
}
