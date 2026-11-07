///|
/// A controlled switch; the caller supplies its state and handles activation.
pub fn switch_control(
  enabled~ : Bool,
  label~ : String,
  on_click~ : @cmd.Cmd,
  disabled~ : Bool = false,
  title? : String,
) -> @html.Html {
  @html.button(
    class="switch-control",
    type_="button",
    title=title.unwrap_or(label),
    disabled~,
    on_click~,
    attrs=@html.Attrs::build()
      .role("switch")
      .aria_label(label)
      .aria_checked(enabled.to_string()),
    @html.span(class="switch-control-track", ""),
  )
}

///|
/// A form row: name and optional description on the left, the control
/// on the right. `stack=true` drops the control below the text at full
/// width instead, for free-form fields (URLs, keys) that a narrow right
/// column would squeeze.
pub fn form_row(
  name : String,
  controls : Array[@html.Html],
  desc? : String,
  stack~ : Bool = false,
) -> @html.Html {
  let text : Array[@html.Html] = [@html.div(class="form-row-label", name)]
  if desc is Some(desc) && !desc.is_empty() {
    text.push(@html.div(class="form-row-description", desc))
  }
  @html.div(class=if stack { "form-row stack" } else { "form-row" }, [
    @html.div(class="form-row-text", text),
    @html.div(class="form-row-controls", controls),
  ])
}

///|
/// A titled section whose content shares a card surface.
pub fn form_section(
  icon_image : () -> @html.Html,
  title : String,
  rows : Array[@html.Html],
) -> @html.Html {
  @html.div(class="form-section", [
    @html.div(class="form-section-header", [
      @icons.icon(icon_image),
      @html.h2(title),
    ]),
    @html.div(class="form-section-body card-surface", rows),
  ])
}
