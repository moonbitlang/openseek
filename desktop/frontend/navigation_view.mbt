///|
fn navigation_notice(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html? {
  let cloud = model.navigation.location.map_or(false, location => {
    location.target.is_cloud()
  })
  if cloud && model.account is None && model.navigation.phase is Waiting {
    return None
  }
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
      if !cloud && model.navigation.phase is (Failed(_) | Missing) {
        @html.button(
          class="button",
          id="navigation-retry",
          on_click=dispatch(Navigation(Retry)),
          shell_text(model.locale, NavigationRetry),
        )
      } else {
        @html.div(@html.nothing)
      },
    ]),
  )
}
