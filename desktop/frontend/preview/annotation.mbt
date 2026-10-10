///|
pub(all) enum Annotation {
  Idle
  Selecting
  Failed(String)
} derive(Eq)

///|
pub(all) enum AnnotationMsg {
  Start
  Cancel
  Picked(request~ : String, Result[@protocol.BrowserPickReply, String])
}

///|
fn annotation_text(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> String {
  match locale {
    SimplifiedChinese | TraditionalChinese => chinese
    _ => english
  }
}

///|
pub fn annotation_button(
  locale~ : @i18n.Locale,
  state : Annotation,
  emit : @cmd.Emit[AnnotationMsg],
) -> @html.Html {
  let active = state is Selecting
  let label = if active {
    annotation_text(
      locale, "Exit annotation mode (Esc)", "退出标注模式（Esc）",
    )
  } else {
    annotation_text(locale, "Enter annotation mode", "进入标注模式")
  }
  @html.button(
    class=if active {
      "browser-nav-button browser-annotate active"
    } else {
      "browser-nav-button browser-annotate"
    },
    title=label,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .aria_pressed(active.to_string()),
    on_click=emit(if active { Cancel } else { Start }),
    @icons.icon(@icons.icon_comment),
  )
}

///|
pub fn annotation_view(
  locale~ : @i18n.Locale,
  state : Annotation,
  emit : @cmd.Emit[AnnotationMsg],
) -> @html.Html {
  let children : Array[@html.Html] = match state {
    Idle | Selecting => []
    Failed(message) =>
      [
        @html.span(message),
        @html.button(
          on_click=emit(Start),
          annotation_text(locale, "Try again", "重试"),
        ),
        @html.button(
          on_click=emit(Cancel),
          annotation_text(locale, "Dismiss", "关闭"),
        ),
      ]
  }
  @html.div(
    class=if !(state is Failed(_)) {
      "browser-annotation hidden"
    } else {
      "browser-annotation"
    },
    children,
  )
}

///|
pub extend Annotation with Eq::{equal, not_equal}
