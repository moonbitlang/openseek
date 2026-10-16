///|
fn navigation_controls(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="navigation-controls", [
    @html.button(
      class="navigation-back icon-button",
      title=shell_text(model.locale, NavigateBack),
      attrs=@html.Attrs::build()
        .aria_label(shell_text(model.locale, NavigateBack))
        .disabled(!model.navigation.can_back),
      on_click=dispatch(Navigation(Back)),
      @icons.icon(@icons.icon_arrow_left),
    ),
    @html.button(
      class="navigation-forward icon-button",
      title=shell_text(model.locale, NavigateForward),
      attrs=@html.Attrs::build()
        .aria_label(shell_text(model.locale, NavigateForward))
        .disabled(!model.navigation.can_forward),
      on_click=dispatch(Navigation(Forward)),
      @icons.icon(@icons.icon_arrow_left),
    ),
  ])
}

///|
fn navigation_notice(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html? {
  let message = match model.navigation.phase {
    Active => return None
    Waiting | PreparingNew => shell_text(model.locale, NavigationLoading)
    Missing => shell_text(model.locale, NavigationMissing)
    Invalid => shell_text(model.locale, NavigationInvalid)
    Failed(message) => message
  }
  Some(
    @html.section(class="navigation-notice management-page", [
      @html.p(message),
      if model.navigation.phase is (Failed(_) | Missing) {
        @html.button(
          class="button",
          on_click=dispatch(Navigation(Retry)),
          shell_text(model.locale, NavigationRetry),
        )
      } else {
        @html.div(@html.nothing)
      },
    ]),
  )
}
