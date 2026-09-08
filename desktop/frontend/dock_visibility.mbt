// DOM geometry belongs after rendering. Keep the observer with the current
// strip, disconnecting it when the shell replaces/removes that element.

///|
extern "js" fn make_dock_visibility_sync() -> (Bool) -> Unit =
  #| () => {
  #|   let strip = null;
  #|   let active = null;
  #|   const reveal = () => {
  #|     if (!strip || !active || strip.clientWidth === 0) return;
  #|     const viewport = strip.getBoundingClientRect();
  #|     const tab = active.getBoundingClientRect();
  #|     // Scroll only this strip; scrollIntoView can also move the page or
  #|     // other ancestors.
  #|     if (tab.right > viewport.right) strip.scrollLeft += tab.right - viewport.right;
  #|     else if (tab.left < viewport.left) strip.scrollLeft += tab.left - viewport.left;
  #|   };
  #|   const observer = new ResizeObserver(reveal);
  #|   return force => {
  #|     const nextStrip = document.querySelector('.editor-tabs');
  #|     const nextActive = nextStrip?.querySelector('.editor-tab.active') ?? null;
  #|     const changed = strip !== nextStrip || active !== nextActive;
  #|     if (changed) {
  #|       observer.disconnect();
  #|       strip = nextStrip;
  #|       active = nextActive;
  #|       if (strip) observer.observe(strip);
  #|       if (active) observer.observe(active);
  #|     }
  #|     if (changed || force) reveal();
  #|   };
  #| }

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
