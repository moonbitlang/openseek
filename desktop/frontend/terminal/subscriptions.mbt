///|
priv suberror TerminalSubscription {
  TerminalSubscription(@cmd.Emit[ComponentMsg])
}

///|
/// Ctrl+` and changes to the component's rendered input marker are terminal
/// events. Both feed the terminal's own update function directly.
fn terminal_subscription(emit : @cmd.Emit[ComponentMsg]) -> @sub.Sub {
  @sub.custom_sub(
    "terminal-events",
    @sub.Local,
    TerminalSubscription(emit),
    terminal_sub_loader,
  )
}

///|
fn terminal_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    TerminalSubscription(emit) => {
      let mut emit = emit
      let listeners = install_terminal_listeners(
        () => scheduler.add(emit(Terminal(External(ToggleTerminal)))),
        () => scheduler.add(emit(InputRendered)),
      )
      Some({
        unload: _ => remove_terminal_listeners(listeners),
        update_tagger: payload => {
          guard payload is TerminalSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
/// The observer watches one explicit data attribute, not arbitrary DOM growth.
/// Rabbita updates it as the parent `Val[Input]` changes.
extern "js" fn install_terminal_listeners(
  on_toggle : () -> Unit,
  on_input : () -> Unit,
) -> @js.Value =
  #| (onToggle, onInput) => {
  #|   const keydown = (event) => {
  #|     if (event.code !== "Backquote" || !event.ctrlKey || event.shiftKey ||
  #|         event.altKey || event.metaKey || event.isComposing || event.repeat) return;
  #|     onToggle();
  #|   };
  #|   const observer = new MutationObserver((records) => {
  #|     if (records.some((record) => {
  #|       if (record.type === "attributes") {
  #|         return record.attributeName === "data-terminal-input";
  #|       }
  #|       return [...record.addedNodes].some((node) =>
  #|         node.nodeType === Node.ELEMENT_NODE &&
  #|         (node.matches?.(".terminal-panel") ||
  #|          node.querySelector?.(".terminal-panel")),
  #|       );
  #|     })) onInput();
  #|   });
  #|   document.addEventListener("keydown", keydown);
  #|   observer.observe(document.documentElement, {
  #|     attributes: true,
  #|     childList: true,
  #|     subtree: true,
  #|     attributeFilter: ["data-terminal-input"],
  #|   });
  #|   return { keydown, observer };
  #| }

///|
extern "js" fn remove_terminal_listeners(listeners : @js.Value) -> Unit =
  #| (listeners) => {
  #|   document.removeEventListener("keydown", listeners.keydown);
  #|   listeners.observer.disconnect();
  #| }
