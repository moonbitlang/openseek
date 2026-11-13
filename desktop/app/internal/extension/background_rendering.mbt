///|
priv struct BackgroundRendering {
  supported : Bool
  path : @pathx.Path?
  launch_enabled : Bool
  mut enabled : Bool
  mut preference_error : String?
  mut session_error : String?
  write_lock : @async.Mutex
}

///|
priv suberror BackgroundRenderingError {
  BackgroundRenderingError(String)
}

///|
async fn load_background_rendering(
  runtime_dir : String?,
) -> BackgroundRendering {
  let supported = @async.platform is MacOS
  let path = if supported {
    runtime_dir.map(dir => {
      let path : @pathx.Path = dir
      path.join("background-rendering.json")
    })
  } else {
    None
  }
  let (enabled, preference_error) = match path {
    Some(path) =>
      try {
        let text = @fs.read_file(path.to_string()).text()
        let saved : @protocol.BackgroundRenderingSetPayload = @json.from_json(
          @json.parse(text),
        )
        (saved.enabled, None)
      } catch {
        @os_error.OSError(_) as error if error.is_ENOENT() => (false, None)
        _ =>
          (false, Some("Could not read the background rendering preference."))
      }
    None if supported =>
      (false, Some("Background rendering preference storage is unavailable."))
    None => (false, None)
  }
  if preference_error is Some(message) {
    @xlog.warn() <?
      {
        "event": "desktop_background_rendering_preference_failed",
        "message": message,
      }
  }
  {
    supported,
    path,
    launch_enabled: enabled,
    enabled,
    preference_error,
    session_error: None,
    write_lock: Mutex(),
  }
}

///|
fn BackgroundRendering::settings(
  self : BackgroundRendering,
) -> @protocol.BackgroundRenderingSettings {
  {
    supported: self.supported,
    enabled: self.enabled,
    launch_enabled: self.launch_enabled,
    error: if self.session_error is Some(error) {
      Some(error)
    } else {
      self.preference_error
    },
  }
}

///|
async fn BackgroundRendering::save(
  self : BackgroundRendering,
  enabled : Bool,
) -> @protocol.BackgroundRenderingSettings {
  guard self.supported else {
    raise BackgroundRenderingError(
      "Background rendering is available on macOS.",
    )
  }
  guard self.path is Some(path) else {
    raise BackgroundRenderingError(
      "Background rendering preference storage is unavailable.",
    )
  }
  self.write_lock.acquire()
  defer self.write_lock.release()
  let temp = path.dirname().join("background-rendering-\{@uuid.mint()}.tmp")
  defer @async.protect_from_cancel(() => {
    @fs.remove(temp.to_string()) catch { _ => () }
  })
  let preference : @protocol.BackgroundRenderingSetPayload = { enabled, }
  try {
    @fs.write_file(
      temp.to_string(),
      preference.to_json().stringify(),
      create_mode=CreateNew,
    )
    @async.protect_from_cancel(() => {
      @fs.rename(temp.to_string(), path.to_string(), replace=true)
      self.enabled = enabled
      self.preference_error = None
    })
  } catch {
    _ =>
      raise BackgroundRenderingError(
        "Could not save the background rendering preference.",
      )
  }
  self.settings()
}

///|
/// The main page's CDP session keeps focus emulation active until the window closes.
pub async fn BrowserViews::run_background_rendering(
  self : BrowserViews,
  window : @proton.WindowHandle,
  notify_changed : async () -> Unit noraise,
) -> Unit noraise {
  let preference = self.background_rendering
  guard preference.launch_enabled else { return }
  let mut stage = "wait_for_page"
  try {
    // host.connect is sent by the loaded document. Stamping the marker during
    // window creation could put it in the initial about:blank document.
    @async.with_timeout(10000, () => {
      while !self.page_connected {
        @async.sleep(50)
      }
    })
    stage = "find_main_target"
    with_marked_contents_cdp(self.debug_port, window.web_contents(), connection => {
      stage = "enable_focus_emulation"
      connection.set_focus_emulation_enabled(true)
      @xlog.info() <?
        {
          "event": "desktop_background_rendering_enabled",
          "message": "background rendering session enabled",
        }
      defer @xlog.info() <?
        {
          "event": "desktop_background_rendering_closed",
          "message": "background rendering session closed",
        }
      stage = "wait_for_disconnect"
      connection.wait_for_disconnect()
      preference.session_error = Some(
        "Background rendering disconnected. Restart SeekMoon to try again.",
      )
      notify_changed()
    })
  } catch {
    error => {
      let (reason, error_code) = match error {
        @async.TimeoutError => ("timeout", Json::null())
        @cdp.CommandFailed(code~, ..) => ("cdp_command_failed", Json(code))
        @cdp.Protocol(_) => ("cdp_protocol_error", Json::null())
        _ => ("operation_failed", Json::null())
      }
      preference.session_error = Some(
        "Background rendering could not stay active. Restart SeekMoon to try again.",
      )
      @xlog.warn() <?
        {
          "event": "desktop_background_rendering_failed",
          "message": "background rendering session failed",
          "stage": stage,
          "reason": reason,
          "error_code": error_code,
        }
      notify_changed()
    }
  }
}
