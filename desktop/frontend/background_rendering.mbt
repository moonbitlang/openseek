///|
priv suberror BackgroundRenderingSubscription {
  BackgroundRenderingSubscription(@cmd.Emit[Msg])
}

///|
fn background_rendering_subscription(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "background-rendering",
    Global,
    BackgroundRenderingSubscription(emit),
    (payload, scheduler) => {
      guard payload is BackgroundRenderingSubscription(emit) else {
        return None
      }
      guard @interop.moonbit_bridge_root() is Some(bridge) else { return None }
      let mut emit = emit
      let unsubscribe = subscribe_background_rendering_changes(bridge, () => {
        scheduler.add(load_background_rendering(emit))
      })
      Some({
        unload: _ => unsubscribe(),
        update_tagger: payload => {
          if payload is BackgroundRenderingSubscription(next) {
            emit = next
          }
        },
      })
    },
  )
}

///|
fn load_background_rendering(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let status = @interop.bridge_request_in_order(
        Local,
        @commands.app_background_rendering_get,
        @protocol.NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              BackgroundRenderingLoadFailed(@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      scheduler.add(dispatch(BackgroundRenderingLoaded(status)))
    })
    |> ignore
  })
}

///|
fn save_background_rendering(
  dispatch : @cmd.Emit[Msg],
  enabled : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let status = @interop.bridge_request_in_order(
        Local,
        @commands.app_background_rendering_set,
        { enabled, },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              BackgroundRenderingSaveFailed(@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      scheduler.add(dispatch(BackgroundRenderingSaved(status)))
    })
    |> ignore
  })
}

///|
fn settings_experimental_groups(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  guard model.is_desktop else { return [] }
  let rows : Array[@html.Html] = []
  if model.background_rendering_error is Some(error) {
    rows.push(
      @ui.form_row(@settings.text(model.locale, BackgroundRendering), [
        @html.div(attrs=@html.Attrs::build().role("alert"), error),
      ]),
    )
  } else if model.background_rendering is Some(status) && status.supported {
    let controls = [
      @ui.switch_control(
        enabled=status.enabled,
        label=@settings.text(model.locale, BackgroundRendering),
        disabled=model.background_rendering_saving,
        on_click=dispatch(BackgroundRenderingChanged(!status.enabled)),
      ),
    ]
    if status.enabled != status.launch_enabled {
      controls.push(
        @html.span(
          attrs=@html.Attrs::build().role("status"),
          @settings.text(model.locale, RestartRequired),
        ),
      )
    }
    rows.push(
      @ui.form_row(
        @settings.text(model.locale, BackgroundRendering),
        controls,
        desc=@settings.text(model.locale, BackgroundRenderingDescription),
      ),
    )
    if status.error is Some(error) {
      rows.push(@html.div(attrs=@html.Attrs::build().role("alert"), error))
    }
  }
  if rows.is_empty() {
    []
  } else {
    [
      @ui.form_section(
        @icons.icon_settings_gear,
        @settings.text(model.locale, Experimental),
        rows,
      ),
    ]
  }
}
