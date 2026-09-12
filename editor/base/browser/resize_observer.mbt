///|
#external
priv type NativeResizeObserver

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
extern "js" fn try_observe_element_resize(
  target : @rdom.Element,
  notify : () -> Unit,
  observed : (NativeResizeObserver) -> Unit,
) -> Bool =
  #| (target, notify, observed) => {
  #|   const ResizeObserver = target?.ownerDocument?.defaultView?.ResizeObserver
  #|     ?? globalThis.ResizeObserver;
  #|   if (typeof ResizeObserver !== 'function') return false;
  #|   let observer;
  #|   try {
  #|     observer = new ResizeObserver(() => notify());
  #|     observer.observe(target);
  #|     observed(observer);
  #|     return true;
  #|   } catch (_error) {
  #|     observer?.disconnect?.();
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn native_resize_observer_disconnect(
  observer : NativeResizeObserver,
) -> Unit = "observer => observer.disconnect()"
