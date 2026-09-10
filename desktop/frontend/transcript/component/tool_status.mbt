///|
/// A call's recorded outcome, rendered independently of its disclosure body.
/// Partial output still means pending; only a completed result earns a check.
priv struct ToolStatus(@transcript.ToolOutcome)

///|
fn ToolStatus::view(self : ToolStatus) -> @html.Html {
  let (label, class, icon) = match self.0 {
    Pending(..) =>
      (
        "Tool in progress",
        "tool-status pending",
        @html.span(
          class="tool-status-spinner",
          attrs=@html.Attrs::build().aria_hidden("true"),
          @html.nothing,
        ),
      )
    Done(is_error=true, ..) =>
      ("Tool failed", "tool-status failed", @icons.icon(@icons.icon_error))
    Done(..) =>
      (
        "Tool succeeded",
        "tool-status succeeded",
        @icons.icon(@icons.icon_check),
      )
  }
  @html.span(
    class~,
    attrs=@html.Attrs::build().role("img").aria_label(label).title(label),
    icon,
  )
}
