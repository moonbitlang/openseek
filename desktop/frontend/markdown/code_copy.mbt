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
// Only transient DOM attributes are owned here; Rabbita retains ownership of
// both icon subtrees. A per-element timer survives streaming re-renders and
// restarts on repeated copies, without keeping removed buttons in a registry.
extern "js" fn copy_button_feedback(
  button : @dom.EventTarget,
  copied : Bool,
  title : String,
  label : String,
  feedback : String,
) -> Unit =
  #| (() => {
  #|   const timers = new WeakMap();
  #|   return (button, copied, title, label, feedback) => {
  #|     if (!button.isConnected) return;
  #|     const previous = timers.get(button);
  #|     if (previous !== undefined) clearTimeout(previous);
  #|     button.setAttribute("data-copy-state", copied ? "copied" : "failed");
  #|     button.setAttribute("title", feedback);
  #|     button.setAttribute("aria-label", feedback);
  #|     timers.set(button, setTimeout(() => {
  #|       button.removeAttribute("data-copy-state");
  #|       button.setAttribute("title", title);
  #|       button.setAttribute("aria-label", label);
  #|       timers.delete(button);
  #|     }, 2000));
  #|   };
  #| })()
