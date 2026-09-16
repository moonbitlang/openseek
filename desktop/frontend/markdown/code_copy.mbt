///|
fn code_copy_button(source : String) -> @html.Html {
  @html.button(
    class="button secondary chat-code-copy",
    type_="button",
    title="Copy code",
    attrs=@html.Attrs::build()
      .aria_label("Copy code")
      .on_click(event => {
        // Capture currentTarget while the event is being dispatched: the
        // clipboard command completes after the event has left the button.
        guard event.current_target().to_option() is Some(button) else {
          return @cmd.none
        }
        @clipboard.copy(
          @clipboard.Text(source),
          copied=@cmd.custom_cmd(_ => code_copy_feedback(button, true)),
          failed=_ => @cmd.custom_cmd(_ => code_copy_feedback(button, false)),
        )
      }),
    [
      @html.span(class="chat-code-copy-symbol", @icons.icon(@icons.icon_copy)),
      @html.span(class="chat-code-copy-check", @icons.icon(@icons.icon_check)),
    ],
  )
}

///|
// Only transient DOM attributes are owned here; Rabbita retains ownership of
// both icon subtrees. A per-element timer survives streaming re-renders and
// restarts on repeated copies, without keeping removed buttons in a registry.
extern "js" fn code_copy_feedback(
  button : @dom.EventTarget,
  copied : Bool,
) -> Unit =
  #| (() => {
  #|   const timers = new WeakMap();
  #|   return (button, copied) => {
  #|     if (!button.isConnected) return;
  #|     const previous = timers.get(button);
  #|     if (previous !== undefined) clearTimeout(previous);
  #|     button.setAttribute("data-copy-state", copied ? "copied" : "failed");
  #|     const label = copied ? "Copied" : "Copy failed. Try again.";
  #|     button.setAttribute("title", label);
  #|     button.setAttribute("aria-label", label);
  #|     timers.set(button, setTimeout(() => {
  #|       button.removeAttribute("data-copy-state");
  #|       button.setAttribute("title", "Copy code");
  #|       button.setAttribute("aria-label", "Copy code");
  #|       timers.delete(button);
  #|     }, 2000));
  #|   };
  #| })()
