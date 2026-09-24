///|
/// Monaco's `runWhenGlobalIdle`: bind the once-selected adapter to the same
/// `globalThis` realm used for feature detection (`async.ts:1536-1579`).
let browser_tokenization_idle_adapter : TokenizationIdleAdapter = create_tokenization_idle_adapter(
  global_tokenization_idle_target(),
)

///|
fn schedule_tokenization_idle(
  callback : (@model.TokenizationIdleDeadline) -> Unit,
) -> @base_common.Disposable {
  let cancel = run_tokenization_idle_adapter(
    browser_tokenization_idle_adapter,
    deadline => {
      callback(
        TokenizationIdleDeadline(() => {
          browser_idle_deadline_time_remaining(deadline)
        }),
      )
    },
    None,
  )
  @base_common.Disposable::from(cancel)
}

///|
let browser_tokenization_scheduler : @model.TokenizationScheduler = TokenizationScheduler(
  idle=schedule_tokenization_idle,
  zero_timeout=callback => @base_browser.schedule_timeout(callback, 0),
  delay=(milliseconds, callback) => {
    @base_browser.schedule_timeout(callback, milliseconds)
  },
  now=@base_browser.monotonic_now_ms,
)

///|
/// Starts every task in its own JavaScript async continuation and resumes when
/// the last continuation finishes. Completion callbacks therefore observe real
/// completion order while shared packages remain independent of the browser's
/// async runtime.
async fn run_async_tasks_concurrently(tasks : Array[async () -> Unit]) -> Unit {
  if tasks.is_empty() {
    return
  }
  if tasks.length() == 1 {
    tasks[0]()
    return
  }
  @base_browser.wait_callback((resolve : (Unit) -> Unit) => {
    let mut remaining = tasks.length()
    for task in tasks {
      @js.Promise::from_async(() => {
        task() catch {
          _ => ()
        }
        remaining -= 1
        if remaining == 0 {
          resolve(())
        }
      })
      |> ignore
    }
  }) catch {
    _ => ()
  }
}

///|
/// Starts one detached JS async continuation. Freshness/cancellation ownership
/// remains with the request stamp captured by the continuation.
fn launch_async_task(task : async () -> Unit noraise) -> Unit {
  @js.Promise::from_async(() => task()) |> ignore
}
