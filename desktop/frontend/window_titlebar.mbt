// Proton owns native control geometry; this window-local subscription mirrors
// its available titlebar area into CSS and manages the page's drag regions.

///|
const WindowTitlebarSelector = ".sidebar-header, .topbar, .editor-tabsbar, .window-titlebar-drag-strip"

///|
const WindowTitlebarExcludedSelector = "button, a, input, textarea, select, [role=button], [contenteditable=true], .editor-tab, .dock-menu"

///|
fn window_titlebar_drag_strip_visible(
  page_without_topbar : Bool,
  is_desktop : Bool,
) -> Bool {
  page_without_topbar && is_desktop
}

///|
fn is_window_titlebar_double_click_target(element : @dom.Element) -> Bool {
  if element.closest(WindowTitlebarExcludedSelector) is Some(_) {
    return false
  }
  element.closest(WindowTitlebarSelector) is Some(_)
}

///|
/// Geometry is transient renderer state, not a session or host preference.
/// Native state events cover OS fullscreen transitions (which are not DOM
/// fullscreen events); resize also covers page zoom. Only the latest query may
/// publish geometry. Subscription reconciliation republishes CEF drag regions
/// for new DOM without issuing another native query.
extern "js" fn install_window_titlebar_geometry() -> @js.Value =
  #| () => {
  #|   const html = document.documentElement;
  #|   const selector = ".sidebar-header, .topbar, .editor-tabsbar, .window-titlebar-drag-strip";
  #|   const excluded =
  #|     "button, a, input, textarea, select, [role=button], [contenteditable=true], .editor-tab, .dock-menu";
  #|   let active = true;
  #|   let revision = 0;
  #|   let inFlight = false;
  #|   let frame = null;
  #|   let retry = null;
  #|   let unsubscribe = null;
  #|   const refreshDom = () => {
  #|     const drag = html.classList.contains("native-titlebar-overlay");
  #|     for (const root of document.querySelectorAll(selector)) {
  #|       root.style.webkitAppRegion = drag ? "drag" : "no-drag";
  #|       for (const control of root.querySelectorAll(excluded)) {
  #|         control.style.webkitAppRegion = "no-drag";
  #|       }
  #|     }
  #|   };
  #|   const publish = (area) => {
  #|     // null means no overlay (including native fullscreen). A rejected or
  #|     // malformed query must not be mistaken for that successful answer.
  #|     if (area !== null && (
  #|       typeof area !== "object" ||
  #|       ![area.x, area.y, area.width, area.height].every(Number.isFinite) ||
  #|       area.x < 0 || area.y < 0 || area.width <= 0 || area.height <= 0
  #|     )) throw new Error("Invalid Proton titlebar area");
  #|     html.classList.toggle("native-titlebar-overlay", area !== null);
  #|     if (area === null) {
  #|       for (const name of ["left", "right", "height"]) {
  #|         html.style.removeProperty(`--native-titlebar-${name}`);
  #|       }
  #|     } else {
  #|       html.style.setProperty("--native-titlebar-left", `${area.x}px`);
  #|       html.style.setProperty("--native-titlebar-right", `${Math.max(0, window.innerWidth - area.x - area.width)}px`);
  #|       html.style.setProperty("--native-titlebar-height", `${area.y + area.height}px`);
  #|     }
  #|     refreshDom();
  #|   };
  #|   const schedule = () => {
  #|     if (active && !inFlight && frame === null) frame = requestAnimationFrame(read);
  #|   };
  #|   const read = async () => {
  #|     frame = null;
  #|     const requested = revision;
  #|     inFlight = true;
  #|     try {
  #|       const area = await globalThis.__MoonBit__.getTitlebarArea();
  #|       if (active && requested === revision) publish(area);
  #|     } catch (error) {
  #|       if (active && requested === revision) console.error("Titlebar geometry query failed", error);
  #|     } finally {
  #|       inFlight = false;
  #|       if (requested !== revision) schedule();
  #|     }
  #|   };
  #|   const refresh = () => { revision++; schedule(); };
  #|   const connect = (attempt) => {
  #|     if (!active) return;
  #|     const bridge = globalThis.__MoonBit__;
  #|     // Wait for injection, not for compatibility with an older host.
  #|     if (!bridge?.getTitlebarArea || !bridge?.events?.on) {
  #|       if (attempt < 120) retry = setTimeout(() => connect(attempt + 1), 25);
  #|       else console.error("Proton titlebar bridge unavailable");
  #|       return;
  #|     }
  #|     unsubscribe = bridge.events.on("openseek.window.chrome_changed", refresh);
  #|     window.addEventListener("resize", refresh);
  #|     window.addEventListener("focus", refresh);
  #|     document.addEventListener("visibilitychange", refresh);
  #|     refresh();
  #|   };
  #|   connect(0);
  #|   return {
  #|     refreshDom,
  #|     dispose() {
  #|       active = false;
  #|       clearTimeout(retry);
  #|       if (frame !== null) cancelAnimationFrame(frame);
  #|       if (unsubscribe !== null) unsubscribe();
  #|       window.removeEventListener("resize", refresh);
  #|       window.removeEventListener("focus", refresh);
  #|       document.removeEventListener("visibilitychange", refresh);
  #|       publish(null);
  #|     }
  #|   };
  #| }

///|
extern "js" fn window_titlebar_overlay_visible() -> Bool =
  #| () => document.documentElement.classList.contains("native-titlebar-overlay")

///|
priv suberror WindowTitlebarSubscription {
  WindowTitlebarSubscription(@cmd.Emit[Unit])
}

///|
fn window_titlebar_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    WindowTitlebarSubscription(emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let geometry = install_window_titlebar_geometry()
      let listener : @dom.Listener = event => {
        guard window_titlebar_overlay_visible() &&
          event.to_mouse_event() is Some(mouse) &&
          mouse.get_button() == 0 &&
          event.target().to_element() is Some(element) &&
          is_window_titlebar_double_click_target(element) else {
          return
        }
        // A title or workspace label is text in the DOM, but within window
        // chrome it behaves as chrome rather than selectable document text.
        event.prevent_default()
        scheduler.add(emit(()))
      }
      target.add_event_listener_with_options("dblclick", listener, capture=true)
      Some({
        unload: _ => {
          let _ : @js.Value = geometry.apply_with_string(
            "dispose",
            ([] : FixedArray[@js.Value]),
          )
          target.remove_event_listener_with_options(
            "dblclick",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is WindowTitlebarSubscription(next) else { return }
          emit = next
          let _ : @js.Value = geometry.apply_with_string(
            "refreshDom",
            ([] : FixedArray[@js.Value]),
          )
        },
      })
    }
    _ => None
  }
}

///|
/// Install only in the native desktop page. Proton decides whether the current
/// window has an overlay; browser clients never query native window geometry.
fn window_titlebar_subscription(emit : @cmd.Emit[Unit]) -> @sub.Sub {
  @sub.custom_sub(
    "window-titlebar-double-click",
    Global,
    WindowTitlebarSubscription(emit),
    window_titlebar_sub_loader,
  )
}
