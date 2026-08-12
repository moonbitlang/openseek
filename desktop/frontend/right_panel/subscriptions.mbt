///|
priv suberror PanelSubscription {
  PanelSubscription(Bool, @cmd.Emit[ComponentMsg])
}

///|
/// The panel owns every document-level event that changes its local Model:
/// Shift+Cmd/Ctrl+B, click-away menu dismissal, and captured external links.
fn panel_subscriptions(
  model : Model,
  emit : @cmd.Emit[ComponentMsg],
) -> @sub.Sub {
  @sub.custom_sub(
    "right-panel-events",
    @sub.Local,
    PanelSubscription(model.menu_open, emit),
    panel_sub_loader,
  )
}

///|
fn panel_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    PanelSubscription(menu_open, emit) => {
      let mut menu_open = menu_open
      let mut emit = emit
      let listeners = install_panel_listeners(
        () => scheduler.add(emit(External(TogglePanel))),
        () => if menu_open { scheduler.add(emit(CloseMenu)) },
        url => scheduler.add(emit(External(ExternalLink(url)))),
      )
      Some({
        unload: _ => remove_panel_listeners(listeners),
        update_tagger: payload => {
          guard payload is PanelSubscription(next_open, next_emit) else {
            return
          }
          menu_open = next_open
          emit = next_emit
        },
      })
    }
    _ => None
  }
}

///|
/// One capture listener is enough for the panel's three delegated click/key
/// surfaces. Browser pages keep normal navigation; the desktop page retains
/// the existing allowlist before forwarding a URL into the component.
extern "js" fn install_panel_listeners(
  on_toggle : () -> Unit,
  on_close_menu : () -> Unit,
  on_external : (String) -> Unit,
) -> @js.Value =
  #| (onToggle, onCloseMenu, onExternal) => {
  #|   const apple = /Mac|iPhone|iPad|iPod/i.test(
  #|     navigator.userAgentData?.platform || navigator.platform || "",
  #|   );
  #|   const keydown = (event) => {
  #|     const command = apple
  #|       ? event.metaKey && !event.ctrlKey
  #|       : event.ctrlKey && !event.metaKey;
  #|     if (!command || !event.shiftKey || event.altKey || event.isComposing ||
  #|         event.repeat || event.code !== "KeyB") return;
  #|     event.preventDefault();
  #|     event.stopPropagation();
  #|     onToggle();
  #|   };
  #|   const click = (event) => {
  #|     if (!event.target?.closest?.(".tab-add")) onCloseMenu();
  #|     if (event.defaultPrevented || event.button !== 0) return;
  #|     const anchor = event.target?.closest?.("a[href]");
  #|     if (!anchor || anchor.hasAttribute("download")) return;
  #|     let destination;
  #|     try {
  #|       destination = new URL(anchor.getAttribute("href"), document.baseURI);
  #|     } catch {
  #|       return;
  #|     }
  #|     const supported = destination.protocol === "http:" ||
  #|       destination.protocol === "https:" ||
  #|       destination.protocol === "mailto:";
  #|     if (globalThis.__MoonBit__?.openseek) {
  #|       event.preventDefault();
  #|       if (supported) onExternal(destination.href);
  #|       return;
  #|     }
  #|     const leavesOrigin = destination.protocol === "mailto:" ||
  #|       destination.origin !== globalThis.location?.origin;
  #|     if (supported && leavesOrigin) {
  #|       anchor.target = "_blank";
  #|       anchor.rel = "noopener noreferrer";
  #|     }
  #|   };
  #|   document.addEventListener("keydown", keydown, true);
  #|   document.addEventListener("click", click, true);
  #|   return { keydown, click };
  #| }

///|
extern "js" fn remove_panel_listeners(listeners : @js.Value) -> Unit =
  #| (listeners) => {
  #|   document.removeEventListener("keydown", listeners.keydown, true);
  #|   document.removeEventListener("click", listeners.click, true);
  #| }
