///|
pub(all) enum DialogSize {
  Small
  Medium
  Large
}

///|
fn DialogSize::value(self : DialogSize) -> String {
  match self {
    Small => "small"
    Medium => "medium"
    Large => "large"
  }
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
    class?,
    title?,
    hidden?,
    open?,
    closedby~,
    on_close?,
    on_cancel?,
    attrs=ui_attrs(attrs)
      .data_set("slot", "dialog")
      .data_set("size", size.value()),
    [
      @html.div(
        attrs=@html.Attrs::build().data_set("slot", "dialog-content"),
        children,
      ),
      if show_close {
        @html.form(
          method_="dialog",
          attrs=@html.Attrs::build().data_set("slot", "dialog-close-form"),
          @html.button(
            type_="submit",
            class="icon-button",
            attrs=@html.Attrs::build()
              .data_set("slot", "dialog-close")
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
    class?,
    title?,
    attrs=ui_attrs(attrs).data_set("slot", "dialog-header"),
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
    class?,
    title?,
    attrs=ui_attrs(attrs).data_set("slot", "dialog-title"),
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
    class?,
    title?,
    attrs=ui_attrs(attrs).data_set("slot", "dialog-description"),
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
    class?,
    title?,
    attrs=ui_attrs(attrs).data_set("slot", "dialog-body"),
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
    class?,
    title?,
    attrs=ui_attrs(attrs).data_set("slot", "dialog-footer"),
    children,
  )
}
