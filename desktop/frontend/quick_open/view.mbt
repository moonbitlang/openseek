// The palette's markup and the two after-render DOM writes it needs. The
// element ids below are also the handles those writes use, so they are private
// constants rather than literals repeated at each site.

///|
const InputId : String = "quick-open-input"

///|
const ListId : String = "quick-open-list"

///|
fn row_id(index : Int) -> String {
  "quick-open-row-\{index}"
}

///|
/// Move keyboard focus into the palette input once it exists. Opening renders
/// the dialog for the first time, so the write waits for that render.
fn focus_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(InputId).to_option() is Some(input) {
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "focus",
          ([] : FixedArray[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn scroll_selection_after_render(index : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(row_id(index)).to_option()
        is Some(row) {
        row.scroll_into_view_with_options(block="nearest", inline="nearest")
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Codicon class for the LSP SymbolKind numeric wire value. Related kinds are
/// intentionally grouped so the small quick-pick row has a stable visual
/// vocabulary rather than 26 barely distinguishable glyphs.
fn symbol_kind_icon_class(kind : Int?) -> String {
  match kind {
    Some(1) => "codicon-symbol-file"
    Some(2) | Some(3) | Some(4) | Some(19) => "codicon-symbol-namespace"
    Some(5) => "codicon-symbol-class"
    Some(6) | Some(9) | Some(12) | Some(24) => "codicon-symbol-method"
    Some(7) => "codicon-symbol-property"
    Some(8) => "codicon-symbol-field"
    Some(10) => "codicon-symbol-enum"
    Some(11) => "codicon-symbol-interface"
    Some(13)
    | Some(15)
    | Some(16)
    | Some(17)
    | Some(18)
    | Some(20)
    | Some(21) => "codicon-symbol-variable"
    Some(14) => "codicon-symbol-constant"
    Some(22) => "codicon-symbol-enum-member"
    Some(23) => "codicon-symbol-struct"
    Some(25) => "codicon-symbol-operator"
    Some(26) => "codicon-symbol-type-parameter"
    _ => "codicon-symbol-misc"
  }
}

///|
fn Item::icon_class(self : Item) -> String {
  match self {
    FileRow(_) => "codicon-symbol-file"
    SymbolRow(symbol) => symbol_kind_icon_class(symbol.kind)
  }
}

///|
fn key_attrs(emit : @cmd.Emit[Msg], selected : Int?) -> @html.Attrs {
  @html.Attrs::build().on_keydown(event => {
    if event.is_composing() {
      return @cmd.none
    }
    match event.key() {
      "ArrowDown" => {
        event.prevent_default()
        emit(Move(1))
      }
      "ArrowUp" => {
        event.prevent_default()
        emit(Move(-1))
      }
      "Enter" => {
        event.prevent_default()
        // Keyboard and pointer acceptance use the same validated row message,
        // so the shell sees one accept path and one panel reconciliation.
        match selected {
          Some(index) => emit(Pick(index))
          None => @cmd.none
        }
      }
      "Escape" => {
        event.prevent_default()
        emit(Dismiss)
      }
      _ => @cmd.none
    }
  })
}

///|
fn empty_view(open : Open) -> @html.Html {
  let (class, message) = match (open.phase, open.provider()) {
    (Debouncing | Loading, Files) => ("quick-open-empty", "Indexing files…")
    (Debouncing | Loading, Symbols) =>
      ("quick-open-empty", "Searching symbols…")
    (Failed, Files) => ("quick-open-empty error", "File search failed")
    (Failed, Symbols) => ("quick-open-empty error", "Symbol search failed")
    (Ready, Files) => ("quick-open-empty", "No files found")
    (Ready, Symbols) => ("quick-open-empty", "No symbols found")
  }
  @html.div(
    class~,
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    message,
  )
}

///|
/// The palette, or nothing at all while it is closed. Rendering a placeholder
/// rather than dropping the node keeps the shell's overlay child indices
/// stable across open and close.
fn State::view(self : State, emit : @cmd.Emit[Msg]) -> @html.Html {
  guard self.open is Some(open) else { return @html.nothing }
  dialog_view(emit, open)
}

///|
fn dialog_view(emit : @cmd.Emit[Msg], open : Open) -> @html.Html {
  let selected = if open.current() is Some(_) {
    Some(open.selected)
  } else {
    None
  }
  let active_id = selected.map(index => row_id(index)).unwrap_or("")
  let (dialog_label, placeholder, group_label) = if open.provider() is Files {
    ("Search workspace files", "Search files", "Files")
  } else {
    ("Search workspace symbols", "Search symbols", "Symbols")
  }
  let base_input_attrs = key_attrs(emit, selected)
    .id(InputId)
    .role("combobox")
    .aria_label(dialog_label)
    .aria_controls(ListId)
    .aria_expanded("true")
    .aria_autocomplete("list")
    .aria_keyshortcuts("Meta+P Control+P Meta+T Control+T")
    .data_set("focus-owner", "")
  let input_attrs = if active_id.is_empty() {
    base_input_attrs
  } else {
    base_input_attrs.aria_activedescendant(active_id)
  }
  let rows : Array[@html.Html] = [
    for index, item in open.items => {
      let selected = index == open.selected
      @html.div(
        class=if selected {
          "quick-open-row selected"
        } else {
          "quick-open-row"
        },
        attrs=@html.Attrs::build()
          .id(row_id(index))
          .role("option")
          .aria_selected(if selected { "true" } else { "false" })
          .on_mouseenter(_ => emit(Select(index)))
          .on_mousedown(event => {
            event.prevent_default()
            emit(Pick(index))
          }),
        [
          @html.span(
            class="quick-open-kind codicon \{item.icon_class()}",
            attrs=@html.Attrs::build().aria_hidden("true"),
            ([] : Array[@html.Html]),
          ),
          @html.div(class="quick-open-row-text", [
            @html.div(class="quick-open-name", item.name()),
            @html.div(class="quick-open-detail", item.detail()),
          ]),
        ],
      )
    }
  ]
  let list_children = if rows.is_empty() { [empty_view(open)] } else { rows }
  let list_busy = match open.phase {
    Debouncing | Loading => "true"
    _ => "false"
  }
  @html.div(class="quick-open-backdrop", on_click=emit(Dismiss), [
    @html.div(
      class="quick-open-dialog",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_label(dialog_label)
        .on_click(event => {
          event.stop_propagation()
          @cmd.none
        }),
      [
        @html.div(class="quick-open-input-wrap", [
          @icons.icon(@icons.icon_search),
          @html.input(
            input_type=@html.InputType::Text,
            value=open.value,
            placeholder~,
            on_input=emit.map(value => ValueChanged(value)),
            attrs=input_attrs,
          ),
        ]),
        @html.div(
          class="quick-open-group-label",
          attrs=@html.Attrs::build().id("quick-open-group-label"),
          group_label,
        ),
        @html.div(
          class="quick-open-list",
          attrs=@html.Attrs::build()
            .id(ListId)
            .role("listbox")
            .aria_labelledby("quick-open-group-label")
            .aria_busy(list_busy),
          list_children,
        ),
      ],
    ),
  ])
}
