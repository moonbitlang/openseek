// DOM geometry belongs after rendering. Keep the observer with the current
// strip, disconnecting it when the shell replaces/removes that element.

///|
fn same_dock_element(left : @dom.Element?, right : @dom.Element?) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) => left.is_same_node(right.as_node())
    _ => false
  }
}

///|
fn make_dock_visibility_sync() -> (Bool) -> Unit {
  let mut strip : @dom.Element? = None
  let mut active : @dom.Element? = None
  let reveal = () => {
    guard strip is Some(strip) && active is Some(active) else { return }
    if strip.get_client_width() == 0 {
      return
    }
    let viewport = strip.get_bounding_client_rect()
    let tab = active.get_bounding_client_rect()
    // Scroll only this strip; scrollIntoView can also move other ancestors.
    if tab.get_right() > viewport.get_right() {
      strip.set_scroll_left(
        strip.get_scroll_left() + tab.get_right() - viewport.get_right(),
      )
    } else if tab.get_left() < viewport.get_left() {
      strip.set_scroll_left(
        strip.get_scroll_left() + tab.get_left() - viewport.get_left(),
      )
    }
  }
  let observer = @dom.ResizeObserver::new((_, _) => reveal())
  force => {
    let next_strip = @dom.document().query_selector(".editor-tabs").to_option()
    let next_active = next_strip.bind(strip => {
      strip.query_selector(".editor-tab.active")
    })
    let changed = !same_dock_element(strip, next_strip) ||
      !same_dock_element(active, next_active)
    if changed {
      observer.disconnect()
      strip = next_strip
      active = next_active
      if strip is Some(strip) {
        observer.observe(strip)
      }
      if active is Some(active) {
        observer.observe(active)
      }
    }
    if changed || force {
      reveal()
    }
  }
}

///|
let dock_visibility_sync : Ref[((Bool) -> Unit)?] = Ref(None)

///|
fn sync_dock_visibility(reveal : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      let sync = match dock_visibility_sync.val {
        Some(sync) => sync
        None => {
          let sync = make_dock_visibility_sync()
          dock_visibility_sync.val = Some(sync)
          sync
        }
      }
      sync(reveal)
    },
    kind=@cmd.after_render,
  )
}
