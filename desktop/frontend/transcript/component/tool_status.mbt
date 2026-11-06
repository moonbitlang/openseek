///|
/// A call's recorded outcome, rendered independently of its disclosure body.
/// Partial output still means pending; only a completed result earns a check.
#derive(Eq)
priv enum ToolStatus {
  Snapshot
  Pending
  Succeeded
  Failed
}

///|
/// Share presentation state without retaining tool arguments or result output.
fn ToolStatus::from_outcome(outcome : @transcript.ToolOutcome) -> ToolStatus {
  match outcome {
    Snapshot(..) => Snapshot
    Pending(..) => Pending
    Done(is_error=true, ..) => Failed
    Done(..) => Succeeded
  }
}

///|
fn ToolStatus::view(
  locale~ : @i18n.Locale = English,
  self : ToolStatus,
) -> @html.Html {
  let (label, class, icon) = match self {
    Snapshot =>
      (ui(locale, RecordedSnapshot), "tool-status snapshot", @html.text("·"))
    Pending =>
      (
        ui(locale, ToolInProgress),
        "tool-status pending",
        @html.span(
          class="tool-status-spinner",
          attrs=@html.Attrs::build().aria_hidden("true"),
          @html.nothing,
        ),
      )
    Failed =>
      (
        ui(locale, ToolFailed),
        "tool-status failed",
        @icons.icon(@icons.icon_error),
      )
    Succeeded =>
      (
        ui(locale, ToolSucceeded),
        "tool-status succeeded",
        @icons.icon(@icons.icon_check),
      )
  }
  @html.span(
    class~,
    attrs=@html.Attrs::build()
      .data_set(
        "tool-status",
        match self {
          Snapshot => "snapshot"
          Pending => "pending"
          Succeeded => "succeeded"
          Failed => "failed"
        },
      )
      .role("img")
      .aria_label(label)
      .title(label),
    icon,
  )
}
