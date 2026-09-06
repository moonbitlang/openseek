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
/// Live app typography and colors resolved into values xterm accepts.
priv struct TerminalStyle {
  font_family : String
  font_size : Double
  background : String
  foreground : String
  selection : String
}

///|
/// The emulators' imperative state, keyed by tab key. `pending` buffers
/// output chunks that arrived before any tab claimed their session id (the
/// host streams from spawn, so a session's first output can beat the
/// `terminal_open` reply that names it); `Opened` flushes them into the
/// claiming tab.
priv struct TermHost {
  entries : Map[String, TermEntry]
  /// Root-owned terminal state projected into the imperative output path.
  /// The projection is refreshed only after terminal lifecycle transitions;
  /// raw output reads it without publishing a Rabbita message.
  mut owners : Map[String, (@interop.ChannelId, String)]
  mut opening_channels : Array[@interop.ChannelId]
  /// Output that arrived before `terminal_open` identified its tab:
  /// `(sequence, base64_data)`.
  pending : Map[String, (@interop.ChannelId, Array[(Int, String)])]
  mut resize_wired : Bool
}

///|
let term_host : TermHost = {
  entries: Map([]),
  owners: Map([]),
  opening_channels: [],
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
/// typography and palette through Rabbita's DOM package before crossing the
/// xterm object boundary.
fn terminal_style() -> @js.Value {
  let resolved : TerminalStyle = match @dom.document().get_document_element() {
    Some(root) => {
      let style = @dom.window().get_computed_style(root)
      let font_size_text = style
        .get_property_value("--font-size-sm")
        .trim()
        .to_owned()
      let font_size = match font_size_text.strip_suffix("px") {
        Some(value) => @string.parse_double(value) catch { _ => 13.0 }
        None => 13.0
      }
      let font_family = style
        .get_property_value("--font-family-mono")
        .trim()
        .to_owned()
      let background = style
        .get_property_value("--color-bg-surface")
        .trim()
        .to_owned()
      let foreground = style
        .get_property_value("--color-text-primary")
        .trim()
        .to_owned()
      let selection = style
        .get_property_value("--color-text-selection")
        .trim()
        .to_owned()
      { font_family, font_size, background, foreground, selection, }
    }
    None =>
      {
        font_family: "monospace",
        font_size: 13.0,
        background: "#ffffff",
        foreground: "#16171a",
        selection: "#eef2fe",
      }
  }
  let theme = @js.Object::new()
  theme["background"] = resolved.background
  theme["foreground"] = resolved.foreground
  theme["cursor"] = resolved.foreground
  // xterm's default selection is translucent white, which disappears against
  // OpenSeek's white light-theme surface. Use the app's text-selection token
  // so normal text, the editor, and the terminal stay visually consistent.
  theme["selectionBackground"] = resolved.selection
  theme["selectionInactiveBackground"] = resolved.selection
  let result = @js.Object::new()
  result["fontFamily"] = resolved.font_family
  result["fontSize"] = resolved.font_size
  result["theme"] = theme.to_value()
  result.to_value()
}

///|
fn no_args() -> Array[@js.Value] {
  []
}

///|
/// Show `key`'s element, hide the rest, then re-fit and focus the shown one
/// (its `onResize` keeps the PTY's grid in sync). Imperative display state:
/// the elements are outside the virtual DOM.
fn show_only(key : String) -> Unit {
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
fn mount_tab(dispatch : @cmd.Emit[Msg], key : String) -> @cmd.Cmd {
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
        term_host.entries[key] = { term, fit, element, }
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
fn apply_shown(key : String?) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
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
    _ => {
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
  @cmd.custom_cmd(_ => {
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
  @cmd.custom_cmd(_ => {
    for _, entry in term_host.entries {
      let options : @js.Value = entry.term.get_with_string("options")
      options.set_with_string("fontSize", @js.Value::cast_from(font_size))
    }
    refit_visible()
  })
}

///|
/// Project the root-owned session bindings into the high-frequency output
/// path. This command runs after terminal reconciliation, so `owners` and
/// `opening_channels` always describe the same accepted State without making
/// raw output enter the root update loop.
fn State::sync_host_routes(self : State) -> @cmd.Cmd {
  let owners : Map[String, (@interop.ChannelId, String)] = Map([])
  let opening_channels : Array[@interop.ChannelId] = []
  for tab in self.tabs {
    match tab.id {
      Some(id) => owners[id] = (tab.workspace.channel(), tab.key)
      None if tab.status is TabOpening => {
        let channel = tab.workspace.channel()
        if !opening_channels.contains(channel) {
          opening_channels.push(channel)
        }
      }
      None => ()
    }
  }
  @cmd.custom_cmd(_ => {
    term_host.owners = owners
    term_host.opening_channels = opening_channels
  })
}

///|
/// Write one accepted chunk to a specific emulator and acknowledge it after
/// xterm renders it. A missing emulator still consumes the chunk: retaining
/// its acknowledgement would stall every later chunk in the host window.
fn TermHost::write_to_tab(
  self : TermHost,
  channel : @interop.ChannelId,
  key : String,
  id : String,
  sequence : Int,
  data : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard self.entries.get(key) is Some(entry) &&
      xterm_module() is Some(module_) else {
      scheduler.add(TerminalAck::{ channel, id, sequence, }.send())
      return
    }
    let done = (_ : @js.Value) => {
      scheduler.add(TerminalAck::{ channel, id, sequence, }.send())
    }
    let _ : @js.Value = module_.apply_with_string("writeBase64", [
      entry.term,
      @js.Value::cast_from(data),
      @js.Value::cast_from(done),
    ])
  })
}

///|
/// Decode one base64 output chunk into its emulator and acknowledge it after
/// xterm renders it. Output that races `terminal_open` is buffered while that
/// channel has an opening tab; an unrelated/stale session is acknowledged and
/// dropped so it cannot consume the host's flow-control window.
pub fn output(
  channel : @interop.ChannelId,
  id : String,
  sequence : Int,
  data : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    match term_host.owners.get(id) {
      Some((owner_channel, key)) =>
        scheduler.add(
          term_host.write_to_tab(owner_channel, key, id, sequence, data),
        )
      None =>
        if term_host.opening_channels.contains(channel) {
          let (pending_channel, chunks) = match term_host.pending.get(id) {
            Some(pending) => pending
            None => (channel, [])
          }
          chunks.push((sequence, data))
          term_host.pending[id] = (pending_channel, chunks)
        } else {
          scheduler.add(TerminalAck::{ channel, id, sequence, }.send())
        }
    }
  })
}

///|
/// Flush chunks buffered for `id` into the tab that just claimed it. Every
/// flushed chunk goes through the normal write path, so each one is
/// acknowledged as it renders.
fn flush_pending(key : String, id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard term_host.pending.get(id) is Some((channel, chunks)) else { return }
    term_host.pending.remove(id)
    for chunk in chunks {
      // The accepted Opened transition supplies the key directly; its route
      // projection is scheduled by reconciliation immediately afterward.
      scheduler.add(term_host.write_to_tab(channel, key, id, chunk.0, chunk.1))
    }
  })
}

///|
/// Drop any buffer for a session that ended unclaimed, acknowledging the
/// bytes so the host's window is released before the session's teardown.
fn drop_pending(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard term_host.pending.get(id) is Some((channel, chunks)) else { return }
    term_host.pending.remove(id)
    for chunk in chunks {
      scheduler.add(TerminalAck::{ channel, id, sequence: chunk.0, }.send())
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
  @cmd.custom_cmd(_ => {
    term_host.owners.retain((_, owner) => owner.0 != channel)
    term_host.opening_channels = term_host.opening_channels.filter(existing => {
      existing != channel
    })
    self.pending.retain((_, pending) => pending.0 != channel)
  })
}

///|
/// Dispose a closed tab's emulator and remove its element.
fn dispose_tab(key : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    term_host.owners.retain((_, owner) => owner.1 != key)
    guard term_host.entries.get(key) is Some(entry) else { return }
    term_host.entries.remove(key)
    let _ : @js.Value = entry.term.apply_with_string("dispose", no_args())
    let _ : @js.Value = entry.element.apply_with_string("remove", no_args())
  })
}
