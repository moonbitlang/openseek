///|
/// Observes `target` with the `ResizeObserver` constructor from its owning
/// window. The global constructor is used only by narrow non-browser test DOMs
/// without `ownerDocument.defaultView`. Creation and `observe` failures are
/// reported as `None`; the returned lifetime is idempotent.
pub fn observe_element_resize(
  target : @rdom.Element,
  notify : () -> Unit,
) -> @base_common.Disposable? {
  let mut native : NativeResizeObserver? = None
  let observed = try_observe_element_resize(target, notify, observer => {
    native = Some(observer)
  })
  if !observed {
    return None
  }
  guard native is Some(observer) else { return None }
  Some(
    @base_common.Disposable::from(() => {
      native_resize_observer_disconnect(observer)
    }),
  )
}

///|
fn try_observe_element_resize(
  target : @rdom.Element,
  notify : () -> Unit,
  observed : (NativeResizeObserver) -> Unit,
) -> Bool {
  guard resize_observer_class(target).to_option() is Some(observer_class) else {
    return false
  }
  let mut created : NativeResizeObserver? = None
  @js.Error_::wrap(
    () => {
      let observer : NativeResizeObserver = observer_class.new([notify])
      created = Some(observer)
      let _ : Unit = @js.Value::cast_from(observer).apply_with_string(
        "observe",
        [target],
      )
      observed(observer)
      @js.Value::cast_from(true)
    },
    map_ok=value => (value.cast() : Bool),
  ) catch {
    _ => {
      if created is Some(observer) {
        let value = @js.Value::cast_from(observer)
        let disconnect : @js.Nullable[@js.Value] = value.get_with_string(
          "disconnect",
        )
        if disconnect.to_option() is Some(_) {
          let _ : Unit = value.apply_with_string(
            "disconnect",
            ([] : FixedArray[@js.Value]),
          )
        }
      }
      false
    }
  }
}
