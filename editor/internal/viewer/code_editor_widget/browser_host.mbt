///|
#external
priv type TokenizationIdleTarget

///|
#external
priv type BrowserIdleDeadline

///|
#external
priv type TokenizationIdleAdapter

///|
extern "js" fn global_tokenization_idle_target_js() -> TokenizationIdleTarget = "() => globalThis"

///|
/// Selects Monaco's browser-idle implementation once for one realm. The
/// injected target is the exact local test seam; production constructs one
/// process-global adapter from `globalThis` below.
extern "js" fn create_tokenization_idle_adapter_js(
  target : TokenizationIdleTarget,
) -> TokenizationIdleAdapter =
  #| (target) => {
  #|   let runWhenIdle;
  #|   if (typeof target.requestIdleCallback !== "function" ||
  #|       typeof target.cancelIdleCallback !== "function") {
  #|     runWhenIdle = (_targetWindow, runner, _timeout) => {
  #|       target.setTimeout(() => {
  #|         if (disposed) return;
  #|         const end = target.Date.now() + 15;
  #|         const deadline = {
  #|           didTimeout: true,
  #|           timeRemaining() {
  #|             return Math.max(0, end - target.Date.now());
  #|           },
  #|         };
  #|         runner(Object.freeze(deadline));
  #|       }, 0);
  #|       let disposed = false;
  #|       return () => {
  #|         if (disposed) return;
  #|         disposed = true;
  #|       };
  #|     };
  #|   } else {
  #|     runWhenIdle = (targetWindow, runner, timeout) => {
  #|       const handle = targetWindow.requestIdleCallback(
  #|         runner,
  #|         typeof timeout === "number" ? { timeout } : undefined,
  #|       );
  #|       let disposed = false;
  #|       return () => {
  #|         if (disposed) return;
  #|         disposed = true;
  #|         targetWindow.cancelIdleCallback(handle);
  #|       };
  #|     };
  #|   }
  #|   return (runner, hasTimeout, timeout) =>
  #|     runWhenIdle(target, runner, hasTimeout ? timeout : undefined);
  #| }

///|
extern "js" fn run_tokenization_idle_adapter_js(
  adapter : TokenizationIdleAdapter,
  callback : (BrowserIdleDeadline) -> Unit,
  has_timeout : Bool,
  timeout : Double,
) -> () -> Unit = "(adapter, callback, hasTimeout, timeout) => adapter(callback, hasTimeout, timeout)"

///|
extern "js" fn browser_idle_deadline_time_remaining_js(
  deadline : BrowserIdleDeadline,
) -> Double = "(deadline) => deadline.timeRemaining()"

///|
/// Monaco's `runWhenGlobalIdle`: bind the once-selected adapter to the same
/// `globalThis` realm used for feature detection (`async.ts:1536-1579`).
let browser_tokenization_idle_adapter : TokenizationIdleAdapter = create_tokenization_idle_adapter_js(
  global_tokenization_idle_target_js(),
)

///|
fn schedule_tokenization_idle(
  callback : (@model.TokenizationIdleDeadline) -> Unit,
) -> @base_common.Disposable {
  let cancel = run_tokenization_idle_adapter_js(
    browser_tokenization_idle_adapter,
    deadline => {
      callback(
        TokenizationIdleDeadline(() => {
          browser_idle_deadline_time_remaining_js(deadline)
        }),
      )
    },
    false,
    0.0,
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
  @js.suspend((resolve : (Unit) -> Unit, _reject : (Error) -> Unit) => {
    let mut remaining = tasks.length()
    for task in tasks {
      @js.async_run(() => {
        task() catch {
          _ => ()
        }
        remaining -= 1
        if remaining == 0 {
          resolve(())
        }
      })
    }
  }) catch {
    _ => ()
  }
}

///|
/// Starts one detached JS async continuation. Freshness/cancellation ownership
/// remains with the request stamp captured by the continuation.
fn launch_async_task(task : async () -> Unit noraise) -> Unit {
  @js.async_run(task)
}
