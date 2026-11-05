///|
fn title(locale : @i18n.Locale) -> String {
  match locale {
    SimplifiedChinese => "导入对话"
    TraditionalChinese => "匯入對話"
    Japanese => "インポートした履歴"
    Spanish => "Historial importado"
    English => "Import conversation"
  }
}

///|
fn label(locale : @i18n.Locale, english : String, chinese : String) -> String {
  match locale {
    SimplifiedChinese | TraditionalChinese => chinese
    _ => english
  }
}

///|
pub fn Model::view(
  self : Model,
  locale : @i18n.Locale,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let children = if self.content is Some(content) {
    let busy = content.operation.busy()
    [
      @rui.dialog_header([
        @rui.dialog_title(id="session-import-title", title(locale)),
        @html.button(
          class="icon-button",
          on_click=emit(Close),
          attrs=@html.Attrs::build().aria_label(
            label(locale, "Close imported history", "关闭导入历史"),
          ),
          @icons.icon(@icons.icon_close),
        ),
      ]),
      @html.div([
        @rui.dialog_description(
          label(
            locale, "Import as a conversation you can continue in the current workspace. Original workspace files are not imported.",
            "导入后可在当前工作区继续聊天。原工作区文件不会随对话一起导入。",
          ),
        ),
        @html.div(class="session-import-actions", [
          @html.button(
            class="button secondary",
            disabled=busy,
            on_click=emit(PickFile),
            label(locale, "Import JSON file", "导入 JSON 文件"),
          ),
          @html.input(
            value=content.link,
            placeholder=label(
              locale, "OpenSeek share link", "OpenSeek 分享链接",
            ),
            on_input=emit.map(value => LinkChanged(value)),
            attrs=@html.Attrs::build()
              .aria_label(
                label(locale, "OpenSeek share link", "OpenSeek 分享链接"),
              )
              .data_set("focus-owner", "true"),
          ),
          @html.button(
            class="button primary",
            disabled=busy || content.link.is_blank(),
            on_click=emit(ImportLink),
            label(locale, "Import link", "导入链接"),
          ),
        ]),
        @html.div(
          class="session-import-status",
          attrs=@html.Attrs::build().role("status"),
          match content.operation {
            Ready => ""
            Reading =>
              label(locale, "Choose a JSON file…", "请选择 JSON 文件…")
            Importing => label(locale, "Importing…", "正在导入…")
            Failed(message) => message
          },
        ),
      ]),
    ]
  } else {
    []
  }
  @rui.dialog(
    id=DialogId,
    class="dialog-size-medium",

    show_close=false,
    on_cancel=emit(Close),
    attrs=@html.Attrs::build().aria_labelledby("session-import-title"),
    children,
  )
}
