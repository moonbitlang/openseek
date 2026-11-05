///|
pub(all) enum DialogSize {
  Small
  Medium
  Large
}

///|
fn DialogSize::class_name(self : DialogSize) -> String {
  match self {
    Small => "desktop-dialog-small"
    Medium => "desktop-dialog-medium"
    Large => "desktop-dialog-large"
  }
}

///|
fn component_class(base : String, extra : String?) -> String {
  extra.map_or(base, extra => base + " " + extra)
}

///|
/// Visibility and focus belong to the native dialog API. Keep the content
/// mounted independently of opening and closing the window.
///
/// `on_cancel` intercepts native close requests; `on_close` reports a completed
/// native close, not the end of a CSS exit transition. The optional close button
/// submits a native dialog form. Callers that must intercept that button use
/// `show_close=false` and supply their own action.
pub fn[C : @html.IsChildren] dialog(
  id? : String,
  class? : String,
  title? : String,
  hidden? : Bool,
  open? : Bool,
  size~ : DialogSize = Medium,
  closedby~ : String = "any",
  show_close~ : Bool = true,
  close_label~ : String = "Close",
  on_close? : @cmd.Emit[String],
  on_cancel? : @cmd.Cmd,
  attrs? : @html.Attrs,
  children : C,
) -> @html.Html {
  @html.dialog(
    id?,
    class=component_class("desktop-dialog " + size.class_name(), class),
    title?,
    hidden?,
    open?,
    closedby~,
    on_close?,
    on_cancel?,
    attrs?,
    [
      @html.div(class="desktop-dialog-content", children),
      if show_close {
        @html.form(
          method_="dialog",
          class="desktop-dialog-close-form",
          @html.button(
            type_="submit",
            class="icon-button desktop-dialog-close",
            attrs=@html.Attrs::build()
              .aria_label(close_label)
              .formnovalidate(true),
            @icons.icon(@icons.icon_close),
          ),
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
pub fn[C : @html.IsChildren] dialog_header(
  id? : String,
  class? : String,
  title? : String,
  attrs? : @html.Attrs,
  children : C,
) -> @html.Html {
  @html.div(
    id?,
    class=component_class("desktop-dialog-header", class),
    title?,
    attrs?,
    children,
  )
}

///|
pub fn[C : @html.IsChildren] dialog_title(
  id? : String,
  class? : String,
  title? : String,
  attrs? : @html.Attrs,
  children : C,
) -> @html.Html {
  @html.h2(
    id?,
    class=component_class("desktop-dialog-title", class),
    title?,
    attrs?,
    children,
  )
}

///|
pub fn[C : @html.IsChildren] dialog_description(
  id? : String,
  class? : String,
  title? : String,
  attrs? : @html.Attrs,
  children : C,
) -> @html.Html {
  @html.p(
    id?,
    class=component_class("desktop-dialog-description", class),
    title?,
    attrs?,
    children,
  )
}

///|
pub fn[C : @html.IsChildren] dialog_body(
  id? : String,
  class? : String,
  title? : String,
  attrs? : @html.Attrs,
  children : C,
) -> @html.Html {
  @html.div(
    id?,
    class=component_class("desktop-dialog-body", class),
    title?,
    attrs?,
    children,
  )
}

///|
pub fn[C : @html.IsChildren] dialog_footer(
  id? : String,
  class? : String,
  title? : String,
  attrs? : @html.Attrs,
  children : C,
) -> @html.Html {
  @html.div(
    id?,
    class=component_class("desktop-dialog-actions", class),
    title?,
    attrs?,
    children,
  )
}
