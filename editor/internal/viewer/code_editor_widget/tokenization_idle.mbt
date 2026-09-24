///|
#external
priv type TokenizationIdleTarget

///|
#external
priv type BrowserIdleDeadline

///|
priv struct TokenizationIdleAdapter {
  target : TokenizationIdleTarget
  native : Bool
}

///|
fn global_tokenization_idle_target() -> TokenizationIdleTarget {
  @js.globalThis.cast()
}

///|
/// Select the implementation once per realm, matching Monaco's runWhenIdle.
fn create_tokenization_idle_adapter(
  target : TokenizationIdleTarget,
) -> TokenizationIdleAdapter {
  let value = @js.Value::cast_from(target)
  {
    target,
    native: is_js_function(value.get_with_string("requestIdleCallback")) &&
    is_js_function(value.get_with_string("cancelIdleCallback")),
  }
}

///|
fn run_tokenization_idle_adapter(
  adapter : TokenizationIdleAdapter,
  callback : (BrowserIdleDeadline) -> Unit,
  timeout : Double?,
) -> () -> Unit {
  let target = @js.Value::cast_from(adapter.target)
  let mut disposed = false
  if adapter.native {
    let options = timeout.map(timeout => {
      let options = @js.Object::new()
      options.set("timeout", timeout)
      options.to_value()
    })
    let handle : @js.Value = target.apply_with_string("requestIdleCallback", [
      @js.Value::cast_from(callback),
      @js.Value::cast_from(@js.Optional::from_option(options)),
    ])
    () => {
      if disposed {
        return
      }
      disposed = true
      let _ : Unit = target.apply_with_string("cancelIdleCallback", [handle])
    }
  } else {
    let run = () => {
      if disposed {
        return
      }
      let date : @js.Value = target.get_with_string("Date")
      let now : Double = date.apply_with_string(
        "now",
        ([] : FixedArray[@js.Value]),
      )
      let end = now + 15.0
      let deadline = @js.Object::new()
      deadline.set("didTimeout", true)
      deadline.set("timeRemaining", () => {
        let now : Double = date.apply_with_string(
          "now",
          ([] : FixedArray[@js.Value]),
        )
        let remaining = end - now
        if remaining > 0.0 {
          remaining
        } else {
          0.0
        }
      })
      let object : @js.Value = @js.globalThis.get_with_string("Object")
      let frozen : BrowserIdleDeadline = object.apply_with_string("freeze", [
        deadline.to_value(),
      ])
      callback(frozen)
    }
    let _ : @js.Value = target.apply_with_string("setTimeout", [
      @js.Value::cast_from(run),
      @js.Value::cast_from(0),
    ])
    // Match Monaco: leave the timer queued and make its callback harmless.
    () => disposed = true
  }
}

///|
fn browser_idle_deadline_time_remaining(
  deadline : BrowserIdleDeadline,
) -> Double {
  @js.Value::cast_from(deadline).apply_with_string(
    "timeRemaining",
    ([] : FixedArray[@js.Value]),
  )
}
