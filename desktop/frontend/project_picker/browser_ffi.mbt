// Browser bindings not yet exposed by Rabbita. Keep foreign definitions
// together, separate from application state and interaction policy.

///|
extern "js" fn clipboard_text(event : @dom.Event) -> @js.Nullable[String] =
  #| event => event.clipboardData?.getData("text/plain") ?? null

///|
extern "js" fn focus_path_input(select_all : Bool) -> Unit =
  #| (selectAll) => {
  #|   const input = document.getElementById("project-picker-path-input");
  #|   if (!input) return;
  #|   input.focus();
  #|   if (selectAll) return input.select();
  #|   const end = input.value.length;
  #|   input.setSelectionRange(end, end);
  #| }
