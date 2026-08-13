// The embedded terminal emulators (packaged xterm.js, loaded as the
// `__openseek_xterm` global by an index.html script tag). Rabbita has no
// escape hatch for foreign DOM widgets, so the panel owns one stable,
// never-diffed container element (`#terminal-host`), and each tab attaches
// its own imperative child element with its own xterm instance — hidden,
// not disposed, while another tab (or none) shows, so every shell's screen
// and scrollback survive tab and conversation switches.

///|
/// The id of the stable container the tab emulators attach into; the panel
/// view must render exactly one empty element with this id.
const TerminalHostId = "terminal-host"

///|
priv struct TermEntry {
  term : @js.Value
  fit : @js.Value
  element : @js.Value
}

///|
/// The emulators' imperative state, keyed by tab key. `pending` buffers
/// output chunks that arrived before any tab claimed their session id (the
/// host streams from spawn, so a session's first output can beat the
/// `terminal_open` reply that names it); `Opened` flushes them into the
/// claiming tab.
priv struct TermHost {
  entries : Map[Int, TermEntry]
  /// Output that arrived before `terminal_open` identified its tab:
  /// `(sequence, base64_data)`.
  pending : Map[(@interop.ChannelId, Int), Array[(Int, String)]]
  mut resize_wired : Bool
}

///|
let term_host : TermHost = {
  entries: Map([]),
  pending: Map([]),
  resize_wired: false,
}

///|
/// The packaged bundle's export object
/// (`{ Terminal, FitAddon, WebLinksAddon, writeBase64 }`).
fn xterm_module() -> @js.Value? {
  @interop.js_prop(@js.globalThis, "__openseek_xterm")
}

///|
/// The emulator cannot consume CSS variables directly, so resolve the live
/// typography and palette at the boundary instead of duplicating them here.
extern "js" fn terminal_style() -> @js.Value =
  #|() => {
  #|  const style = getComputedStyle(document.documentElement);
  #|  const foreground = style.getPropertyValue("--color-text-primary").trim();
  #|  return {
  #|    fontFamily: style.getPropertyValue("--font-family-ui").trim(),
  #|    fontSize: Number.parseFloat(style.getPropertyValue("--font-size-md")),
  #|    theme: {
  #|      background: style.getPropertyValue("--color-bg-surface").trim(),
  #|      foreground,
  #|      cursor: foreground,
  #|    },
  #|  };
  #|}

///|
fn no_args() -> Array[@js.Value] {
  []
}

///|
/// Show `key`'s element, hide the rest, then re-fit and focus the shown one
/// (its `onResize` keeps the PTY's grid in sync). Imperative display state:
/// the elements are outside the virtual DOM.
fn show_only(key : Int) -> Unit {
  for entry_key, entry in term_host.entries {
    let style : @js.Value = entry.element.get_with_string("style")
    style.set_with_string(
      "display",
      if entry_key == key {
        "block"
      } else {
        "none"
      },
    )
  }
  guard term_host.entries.get(key) is Some(entry) else { return }
  let width : Int = entry.element.get_with_string("clientWidth")
  if width > 0 {
    let _ : @js.Value = entry.fit.apply_with_string("fit", no_args())
  }
  let _ : @js.Value = entry.term.apply_with_string("focus", no_args())
}

///|
/// Re-fit whichever tab element is currently visible (the host's size moves
/// with the window, the panel row, and the editor column, all without any
/// tab switch).
fn refit_visible() -> Unit {
  for _, entry in term_host.entries {
    let width : Int = entry.element.get_with_string("clientWidth")
    if width > 0 {
      let _ : @js.Value = entry.fit.apply_with_string("fit", no_args())
    }
  }
}

///|
/// Mount the tab's emulator into the container (a no-op if it already
/// exists), make it the visible one, and report its grid size through
/// `EmulatorReady`. Idempotent: the update loop decides whether a ready
/// report should spawn a session, so re-reports are harmless.
fn mount_tab(dispatch : @cmd.Emit[TerminalMsg], key : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      guard xterm_module() is Some(module_) else { return }
      if term_host.entries.get(key) is None {
        guard @dom.document().get_element_by_id(TerminalHostId).to_option()
          is Some(host) else {
          return
        }
        let document = @js.Value::cast_from(@dom.document())
        let element : @js.Value = document.apply_with_string("createElement", [
          @js.Value::cast_from("div"),
        ])
        element.set_with_string("className", "terminal-instance")
        let _ : @js.Value = @js.Value::cast_from(host).apply_with_string(
          "appendChild",
          [element],
        )
        let options = @js.Object::new()
        let style = terminal_style()
        options["cursorBlink"] = true
        options["fontSize"] = (style.get_with_string("fontSize") : @js.Value)
        options["fontFamily"] = (style.get_with_string("fontFamily") : @js.Value)
        options["scrollback"] = 10000
        options["theme"] = (style.get_with_string("theme") : @js.Value)
        let ctor : @js.Value = module_.get_with_string("Terminal")
        let term : @js.Value = ctor.new([options.to_value()])
        let fit_ctor : @js.Value = module_.get_with_string("FitAddon")
        let fit : @js.Value = fit_ctor.new(no_args())
        let _ : @js.Value = term.apply_with_string("loadAddon", [fit])
        // Let xterm's official addon handle URL parsing, wrapped lines, hover,
        // and ranges. Activation re-enters the app update loop so terminal and
        // transcript links share one navigation policy.
        let on_link = (_event : @js.Value, url : @js.Value) => {
          let url : String = url.cast()
          scheduler.add(dispatch(LinkActivated(url~)))
        }
        let web_links_ctor : @js.Value = module_.get_with_string(
          "WebLinksAddon",
        )
        let web_links : @js.Value = web_links_ctor.new([
          @js.Value::cast_from(on_link),
        ])
        let _ : @js.Value = term.apply_with_string("loadAddon", [web_links])
        let _ : @js.Value = term.apply_with_string("open", [element])
        // Text input from xterm goes to the update loop tagged with this tab;
        // the host encodes this path as UTF-8 for the PTY.
        let on_data = (data : @js.Value) => {
          let text : String = data.cast()
          scheduler.add(dispatch(UserInput(key~, data=text)))
        }
        let _ : @js.Value = term.apply_with_string("onData", [
          @js.Value::cast_from(on_data),
        ])
        // `onBinary` is deliberately separate from `onData`: each JS string
        // code unit is already one terminal byte and must not be UTF-8
        // encoded. Base64 gives the JSON bridge a byte-transparent spelling.
        let on_binary = (data : @js.Value) => {
          let binary : String = data.cast()
          scheduler.add(
            dispatch(
              BinaryInput(key~, data=@terminal_input.encode_binary(binary)),
            ),
          )
        }
        let _ : @js.Value = term.apply_with_string("onBinary", [
          @js.Value::cast_from(on_binary),
        ])
        // Every re-fit lands here, including reveal-time ones; the update
        // loop forwards it to the tab's PTY while its session runs.
        let on_resize = (size : @js.Value) => {
          let cols : Int = size.get_with_string("cols")
          let rows : Int = size.get_with_string("rows")
          scheduler.add(dispatch(ViewportResized(key~, cols~, rows~)))
        }
        let _ : @js.Value = term.apply_with_string("onResize", [
          @js.Value::cast_from(on_resize),
        ])
        term_host.entries[key] = { term, fit, element }
        if !term_host.resize_wired {
          term_host.resize_wired = true
          // The panel's area changes without any window resize — the editor
          // column opening, closing, or being drag-resized all reshape the
          // conversation column the panel sits under — so the refit signal
          // is the host element's own size, not the window's.
          if @interop.js_prop(@js.globalThis, "ResizeObserver") is Some(ctor) {
            let on_resize = (_entries : @js.Value) => refit_visible()
            let observer : @js.Value = ctor.new([
              @js.Value::cast_from(on_resize),
            ])
            let _ : @js.Value = observer.apply_with_string("observe", [
              @js.Value::cast_from(host),
            ])
          }
        }
      }
      show_only(key)
      guard term_host.entries.get(key) is Some(entry) else { return }
      let cols : Int = entry.term.get_with_string("cols")
      let rows : Int = entry.term.get_with_string("rows")
      scheduler.add(dispatch(EmulatorReady(key~, cols~, rows~)))
    },
    kind=@cmd.after_render,
  )
}

///|
fn hide_all() -> Unit {
  for _, entry in term_host.entries {
    let style : @js.Value = entry.element.get_with_string("style")
    style.set_with_string("display", "none")
  }
}

///|
/// Aim the display at one tab's emulator (or none, while the panel is
/// closed): show it, hide the rest, re-fit and focus. `sync` dispatches
/// this whenever the tab that should be on screen changes — including
/// conversation switches, which produce no terminal message of their own.
fn apply_shown(key : Int?) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      match key {
        Some(key) => show_only(key)
        None => hide_all()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Apply the app's current color scheme to every emulator that already
/// exists. Newly mounted tabs receive the same theme in `mount_tab`; this
/// command covers tabs that survive a later light/dark switch.
fn apply_theme() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      let theme : @js.Value = terminal_style().get_with_string("theme")
      for _, entry in term_host.entries {
        let options : @js.Value = entry.term.get_with_string("options")
        options.set_with_string("theme", theme)
      }
    },
    // Theme::apply writes data-theme through the same command batch. Read the
    // computed variables only after that root attribute has landed.
    kind=@cmd.after_render,
  )
}

///|
/// Apply the selected family to every mounted emulator. Future tabs read the
/// same family from the root CSS variable when they mount. Re-fitting the
/// visible emulator updates both xterm's metrics and the PTY grid through the
/// existing `onResize` callback.
pub fn apply_font_family(font_family : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    for _, entry in term_host.entries {
      let options : @js.Value = entry.term.get_with_string("options")
      options.set_with_string("fontFamily", @js.Value::cast_from(font_family))
    }
    refit_visible()
  })
}

///|
/// Apply the selected size to every mounted emulator. Future tabs read the
/// same size from the root CSS token when they mount. Re-fitting reports the
/// resulting grid through xterm's existing `onResize` callback.
pub fn apply_font_size(font_size : Double) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    for _, entry in term_host.entries {
      let options : @js.Value = entry.term.get_with_string("options")
      options.set_with_string("fontSize", @js.Value::cast_from(font_size))
    }
    refit_visible()
  })
}

///|
/// Decode one base64 output chunk into the tab's emulator and report its
/// sequence back once xterm finished rendering it (the flow-control ack).
/// A chunk with no emulator to land in is acknowledged outright — an
/// unacknowledged chunk leaks the host's flow-control window and eventually
/// stalls the session.
fn write_to_tab(
  dispatch : @cmd.Emit[TerminalMsg],
  channel : @interop.ChannelId,
  key : Int,
  id : Int,
  sequence : Int,
  data : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    guard term_host.entries.get(key) is Some(entry) &&
      xterm_module() is Some(module_) else {
      _scheduler.add(dispatch(OutputRendered(channel~, id~, sequence~)))
      return
    }
    let done = (_ : @js.Value) => {
      _scheduler.add(dispatch(OutputRendered(channel~, id~, sequence~)))
    }
    let _ : @js.Value = module_.apply_with_string("writeBase64", [
      entry.term,
      @js.Value::cast_from(data),
      @js.Value::cast_from(done),
    ])
  })
}

///|
/// Stash an output chunk whose session id no tab has claimed yet.
fn buffer_pending(
  channel : @interop.ChannelId,
  id : Int,
  sequence : Int,
  data : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    let owner = (channel, id)
    let chunks = term_host.pending.get(owner).unwrap_or([])
    chunks.push((sequence, data))
    term_host.pending[owner] = chunks
  })
}

///|
/// Flush chunks buffered for `id` into the tab that just claimed it. Every
/// flushed chunk goes through the normal write path, so each one is
/// acknowledged as it renders.
fn flush_pending(
  dispatch : @cmd.Emit[TerminalMsg],
  channel : @interop.ChannelId,
  key : Int,
  id : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let owner = (channel, id)
    guard term_host.pending.get(owner) is Some(chunks) else { return }
    term_host.pending.remove(owner)
    for chunk in chunks {
      scheduler.add(write_to_tab(dispatch, channel, key, id, chunk.0, chunk.1))
    }
  })
}

///|
/// Drop any buffer for a session that ended unclaimed, acknowledging the
/// bytes so the host's window is released before the session's teardown.
fn drop_pending(
  dispatch : @cmd.Emit[TerminalMsg],
  channel : @interop.ChannelId,
  id : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let owner = (channel, id)
    guard term_host.pending.get(owner) is Some(chunks) else { return }
    term_host.pending.remove(owner)
    for chunk in chunks {
      scheduler.add(dispatch(OutputRendered(channel~, id~, sequence=chunk.0)))
    }
  })
}

///|
/// Forget pre-open output owned by a dead WebSocket. Its host-side PTYs and
/// flow-control window disappeared with that connection, so these chunks need
/// neither rendering nor acknowledgement on the replacement connection.
fn TermHost::clear_pending(
  self : TermHost,
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    let owners : Array[(@interop.ChannelId, Int)] = []
    for owner, _ in self.pending {
      if owner.0 == channel {
        owners.push(owner)
      }
    }
    for owner in owners {
      self.pending.remove(owner)
    }
  })
}

///|
/// Dispose a closed tab's emulator and remove its element.
fn dispose_tab(key : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    guard term_host.entries.get(key) is Some(entry) else { return }
    term_host.entries.remove(key)
    let _ : @js.Value = entry.term.apply_with_string("dispose", no_args())
    let _ : @js.Value = entry.element.apply_with_string("remove", no_args())
  })
}
