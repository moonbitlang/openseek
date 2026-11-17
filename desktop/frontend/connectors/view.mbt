///|
pub fn title() -> String {
  "MCP"
}

///|
fn text(locale : @i18n.Locale, english : String, chinese : String) -> String {
  match locale {
    SimplifiedChinese | TraditionalChinese => chinese
    _ => english
  }
}

///|
pub fn view(
  emit : @cmd.Emit[Msg],
  state : State,
  locale : @i18n.Locale,
) -> @html.Html {
  let busy = !(state.operation is Idle)
  let rows : Array[@html.Html] = []
  if state.error is Some(error) {
    rows.push(
      @ui.form_row(
        text(locale, "Authorization failed", "授权失败"),
        [@html.span(class="form-row-status danger", error)],
        stack=true,
      ),
    )
  }
  if state.operation is Loading {
    rows.push(@ui.form_row(text(locale, "Loading…", "加载中…"), []))
  }
  if state.is_empty() {
    rows.push(
      @ui.form_row(
        text(
          locale, "No MCP servers found in installed skills.", "已安装的 skill 中没有 MCP 服务器。",
        ),
        [],
      ),
    )
  }
  for row in state.rows {
    let controls : Array[@html.Html] = []
    if row.error is Some(error) {
      controls.push(@html.span(class="form-row-status danger", error))
    }
    if row.auth == "oauth" {
      if row.error is None {
        controls.push(
          @html.span(
            class=if row.connected {
              "form-row-status success"
            } else {
              "form-row-status"
            },
            if row.connected {
              text(
                locale, "Authorized on this computer", "已在这台电脑上授权",
              )
            } else {
              text(locale, "Not authorized", "未授权")
            },
          ),
        )
      }
      controls.push(
        @html.button(
          class="button",
          disabled=busy,
          on_click=emit(Connect(row.id)),
          if row.connected || row.error is Some(_) {
            text(locale, "Reconnect", "重新授权")
          } else {
            text(locale, "Connect", "连接")
          },
        ),
      )
      if row.connected || row.error is Some(_) {
        controls.push(
          @html.button(
            class="button secondary",
            disabled=busy,
            on_click=emit(Disconnect(row.id)),
            text(locale, "Disconnect", "断开授权"),
          ),
        )
      }
    } else if row.error is None {
      controls.push(
        @html.span(
          class="form-row-status",
          if row.auth == "helper" {
            text(locale, "Uses a credentials helper", "使用凭据 helper")
          } else {
            text(locale, "No sign-in required here", "无需在此登录")
          },
        ),
      )
    }
    rows.push(
      @ui.form_row(
        row.name,
        controls,
        desc=text(locale, "Skill: ", "Skill：") + row.skill,
      ),
    )
    match state.operation {
      Starting(id) if id == row.id =>
        rows.push(
          @ui.form_row(
            text(locale, "Starting authorization…", "正在开始授权…"),
            [],
          ),
        )
      Changing(id) if id == row.id =>
        rows.push(
          @ui.form_row(text(locale, "Updating…", "正在更新…"), []),
        )
      Waiting(id, authorization) if id == row.id =>
        rows.push(
          @ui.form_row(
            text(
              locale, "Complete authorization", "在服务提供商处授权",
            ),
            [
              @html.code(class="form-row-status", authorization.code),
              @html.a(
                class="button",
                href=authorization.url,
                target=Blank,
                rel="noopener noreferrer",
                text(locale, "Open authorization page", "打开授权页面"),
              ),
              @html.button(
                class="button secondary",
                on_click=emit(Cancel),
                text(locale, "Cancel", "取消"),
              ),
            ],
            desc=text(
              locale, "Enter this code on the authorization page. Waiting for your approval…",
              "在授权页面输入设备码，等待你确认授权…",
            ),
            stack=true,
          ),
        )
      _ => ()
    }
  }
  @ui.form_section(@icons.icon_link_external, title(), rows, actions=[
    @html.button(
      class="button",
      disabled=busy,
      on_click=emit(Refresh),
      text(locale, "Refresh", "刷新"),
    ),
  ])
}
