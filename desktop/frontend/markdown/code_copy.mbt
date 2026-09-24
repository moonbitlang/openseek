///|
fn code_copy_button(
  locale? : @i18n.Locale = English,
  source : String,
) -> @html.Html {
  copy_button(
    locale~,
    source,
    class="button secondary chat-code-copy",
    title=match locale {
      SimplifiedChinese => "复制代码"
      TraditionalChinese => "複製程式碼"
      Japanese => "コードをコピー"
      English => "Copy code"
      Spanish => "Copiar código"
    },
    label=match locale {
      SimplifiedChinese => "复制代码"
      TraditionalChinese => "複製程式碼"
      Japanese => "コードをコピー"
      English => "Copy code"
      Spanish => "Copiar código"
    },
  )
}

///|
/// Copies source text and briefly acknowledges successful clipboard writes.
pub fn copy_button(
  locale? : @i18n.Locale = English,
  source : String,
  class~ : String,
  title~ : String,
  label~ : String,
) -> @html.Html {
  @html.button(
    class~,
    type_="button",
    title~,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .on_click(event => {
        // Capture currentTarget while the event is being dispatched: the
        // clipboard command completes after the event has left the button.
        guard event.current_target().to_option() is Some(button) else {
          return @cmd.none
        }
        @clipboard.copy(
          @clipboard.Text(source),
          copied=@cmd.custom_cmd(_ => {
            copy_button_feedback(
              button,
              true,
              title,
              label,
              match locale {
                SimplifiedChinese => "已复制"
                TraditionalChinese => "已複製"
                Japanese => "コピーしました"
                English => "Copied"
                Spanish => "Copiado"
              },
            )
          }),
          failed=_ => {
            @cmd.custom_cmd(_ => {
              copy_button_feedback(
                button,
                false,
                title,
                label,
                match locale {
                  SimplifiedChinese => "复制失败，请重试。"
                  TraditionalChinese => "複製失敗，請重試。"
                  Japanese =>
                    "コピーに失敗しました。再試行してください。"
                  English => "Copy failed. Try again."
                  Spanish => "No se pudo copiar. Inténtalo de nuevo."
                },
              )
            })
          },
        )
      }),
    [
      @html.span(class="copy-button-symbol", @icons.icon(@icons.icon_copy)),
      @html.span(class="copy-button-check", @icons.icon(@icons.icon_check)),
    ],
  )
}

///|
// Weak keys preserve per-button feedback across streaming renders without
// retaining removed DOM nodes. MoonBit owns timer replacement and UI state.
fn copy_button_feedback(
  button : @dom.EventTarget,
  copied : Bool,
  title : String,
  label : String,
  feedback : String,
) -> Unit {
  guard button.to_element() is Some(button) else { return }
  if !button.get_is_connected() {
    return
  }
  let previous : @js.Optional[Int] = copy_feedback_timers.apply_with_string(
    "get",
    [button],
  )
  if previous.to_option() is Some(timer) {
    @dom.window().clear_timeout(timer)
  }
  button.set_attribute(
    "data-copy-state",
    if copied {
      "copied"
    } else {
      "failed"
    },
  )
  button.set_attribute("title", feedback)
  button.set_attribute("aria-label", feedback)
  let timer = @dom.window().set_timeout(
    () => {
      button.remove_attribute("data-copy-state")
      button.set_attribute("title", title)
      button.set_attribute("aria-label", label)
      let _ : Bool = copy_feedback_timers.apply_with_string("delete", [button])
    },
    2000,
  )
  let _ : @js.Value = copy_feedback_timers.apply_with_string("set", [
    @js.Value::cast_from(button),
    @js.Value::cast_from(timer),
  ])
}

///|
let copy_feedback_timers : @js.Value = @js.globalThis.new_with_string(
  "WeakMap",
  ([] : FixedArray[@js.Value]),
)
