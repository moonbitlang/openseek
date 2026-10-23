// The settings-page layout every page that draws one shares: Settings,
// Skills, and a workspace's own settings all build their rows and titled
// cards from here, which is what makes the three read as siblings. Each page
// used to keep its own copy, so the shape had to be changed three times.

///|
/// A controlled on/off switch shared by preference rows and skill enablement.
pub fn switch_control(
  enabled~ : Bool,
  label~ : String,
  on_click~ : @cmd.Cmd,
  disabled~ : Bool = false,
  title? : String,
) -> @html.Html {
  @html.button(
    class="setting-switch",
    type_="button",
    title=title.unwrap_or(label),
    disabled~,
    on_click~,
    attrs=@html.Attrs::build()
      .role("switch")
      .aria_label(label)
      .aria_checked(enabled.to_string()),
    @html.span(class="setting-switch-track", ""),
  )
}

///|
/// One settings row: name and optional description on the left, the control
/// on the right. `stack=true` drops the control below the text at full
/// width instead, for free-form fields (URLs, keys) that a narrow right
/// column would squeeze.
pub fn row(
  name : String,
  controls : Array[@html.Html],
  desc? : String,
  stack~ : Bool = false,
) -> @html.Html {
  let text : Array[@html.Html] = [@html.div(class="setting-name", name)]
  if desc is Some(desc) && !desc.is_empty() {
    text.push(@html.div(class="setting-desc", desc))
  }
  @html.div(class=if stack { "setting-row stack" } else { "setting-row" }, [
    @html.div(class="setting-text", text),
    @html.div(class="setting-control", controls),
  ])
}

///|
/// A titled card of rows: an accent-tinted icon and heading above a bordered
/// surface, the design system's settings section.
pub fn group(
  icon_image : () -> @html.Html,
  title : String,
  rows : Array[@html.Html],
) -> @html.Html {
  @html.div(class="settings-group", [
    @html.div(class="settings-group-head", [
      @icons.icon(icon_image),
      @html.h2(title),
    ]),
    @html.div(class="settings-group-card", rows),
  ])
}
