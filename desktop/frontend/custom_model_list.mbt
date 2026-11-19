// The custom-model section of the API page: the stored entries with their
// edit and delete actions, the delete confirmation, and the editor that
// stands in for the entry it changes.

///|
/// The whole section: one row per stored entry, a confirmation in place of the
/// entry being deleted, and the editor either in place of the entry it edits
/// or closing the list when it adds a new one.
fn custom_model_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let locale = model.locale
  let rows : Array[@html.Html] = []
  let entries = model.custom_models()
  let editing = model.custom_model
  for entry in entries {
    let replaces_this = match editing {
      Some({ original: Some(original), .. }) => original == entry.id
      _ => false
    }
    if replaces_this {
      for row in custom_model_editor_rows(dispatch, model) {
        rows.push(row)
      }
    } else if model.custom_model_delete is Some(id) && id == entry.id {
      for row in custom_model_delete_rows(dispatch, model, entry) {
        rows.push(row)
      }
    } else {
      rows.push(custom_model_entry_row(dispatch, model, entry))
    }
  }
  if entries.is_empty() && editing is None {
    rows.push(@ui.form_row("", [], desc=@settings.text(locale, NoCustomModels)))
  }
  if editing is Some({ original: None, .. }) {
    for row in custom_model_editor_rows(dispatch, model) {
      rows.push(row)
    }
  } else {
    rows.push(custom_model_add_row(dispatch, model))
  }
  rows
}

///|
/// One stored entry: the name it goes by, the id and how many chats use it,
/// and the two actions that own it. The endpoint and key above the list are
/// shared, so nothing here repeats them.
fn custom_model_entry_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  entry : CustomModel,
) -> @html.Html {
  let locale = model.locale
  let usage = match model.custom_model_session_count(entry.id) {
    0 => @settings.text(locale, CustomModelUnused)
    used => @settings.text(locale, CustomModelInUse(used))
  }
  // The connection test runs after the save, so its verdict is the row's: a user
  // who looked away still sees whether the endpoint answered.
  let probe : Array[@html.Html] = match model.custom_model_probe.get(entry.id) {
    Some(Probing) =>
      [
        @html.span(
          class="form-row-status",
          @settings.text(locale, TestingConnection) + "…",
        ),
      ]
    Some(Probed(ok~, detail~)) =>
      [
        @html.span(
          class=if ok {
            "form-row-status success"
          } else {
            "form-row-status danger"
          },
          if ok {
            "✓ " + @settings.text(locale, ConnectionOk)
          } else {
            "✗ \{detail}"
          },
        ),
      ]
    None => []
  }
  @ui.form_row(
    entry.display_name(),
    [
      ..probe,
      @html.button(
        class="button secondary compact",
        type_="button",
        on_click=dispatch(CustomModelEdit(entry.id)),
        @settings.text(locale, EditModel),
      ),
      @html.button(
        class="button danger compact",
        type_="button",
        on_click=dispatch(CustomModelDeleteRequest(entry.id)),
        @settings.text(locale, DeleteModel),
      ),
    ],
    desc="\{entry.id} · \{usage}",
  )
}

///|
/// The confirmation that stands in for the entry about to be deleted. It names
/// the chats the delete would strand, because that is the part a user cannot
/// see from the list itself.
fn custom_model_delete_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  entry : CustomModel,
) -> Array[@html.Html] {
  let locale = model.locale
  let warning = match model.custom_model_session_count(entry.id) {
    0 => @settings.text(locale, DeleteModelUnused)
    used => @settings.text(locale, DeleteModelInUse(used))
  }
  [
    @ui.form_row(
      @settings.text(locale, DeleteModelTitle),
      [
        @html.button(
          class="button danger compact",
          type_="button",
          on_click=dispatch(CustomModelDelete(entry.id)),
          @settings.text(locale, DeleteModel),
        ),
        @html.button(
          class="button secondary compact",
          type_="button",
          on_click=dispatch(CustomModelDeleteCancelled),
          @settings.text(locale, Cancel),
        ),
      ],
      desc="\{entry.display_name()} · \{warning}",
      stack=true,
    ),
  ]
}

///|
/// The row that opens the editor for a new entry. It gives way to the editor
/// itself while that editor is open.
fn custom_model_add_row(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  @ui.form_row("", [
    @html.button(
      class="button secondary compact",
      type_="button",
      on_click=dispatch(CustomModelAdd),
      @settings.text(model.locale, AddModel),
    ),
  ])
}

///|
/// The editor for the draft the page holds: the two fields that name the
/// model, then the row that saves it. Saving probes the endpoint first, so the
/// hint says so and the verdict appears beside the buttons.
fn custom_model_editor_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let locale = model.locale
  guard model.custom_model is Some(draft) else { return [] }
  let field = (
    value : String,
    placeholder : String,
    label : @settings.Message,
    on_input : @cmd.Emit[String],
  ) => {
    @html.input(
      class="setting-input field-surface",
      input_type=@html.InputType::Text,
      value~,
      placeholder~,
      on_input~,
      attrs=@html.Attrs::build()
        .aria_label(@settings.text(locale, label))
        .data_set("focus-owner", ""),
    )
  }
  [
    @ui.form_row(
      @settings.text(locale, ModelId),
      [
        field(
          draft.id,
          "gemini-4-hydrogen",
          ModelId,
          dispatch.map(value => CustomModelIdChanged(value)),
        ),
      ],
      desc=@settings.text(locale, ModelIdHint),
    ),
    @ui.form_row(
      @settings.text(locale, ModelName),
      [
        field(
          draft.label,
          "Gemini 4 Hydrogen",
          ModelName,
          dispatch.map(value => CustomModelLabelChanged(value)),
        ),
        @html.span("\{draft.label.length()}/64"),
      ],
      desc=@settings.text(locale, ModelNameHint),
    ),
    // The window the run plans against. The form states it because no table
    // here can know an arbitrary endpoint's, and the hint doubles as the error
    // text for a value the host would not store.
    @ui.form_row(
      @settings.text(locale, ModelContextWindow),
      [
        field(
          draft.window,
          "1000000",
          ModelContextWindow,
          dispatch.map(value => CustomModelWindowChanged(value)),
        ),
      ],
      desc=if draft.window_ok() {
        @settings.text(locale, ModelContextWindowHint)
      } else {
        @settings.text(locale, ModelContextWindowInvalid)
      },
    ),
    // The hint sits directly left of the compact save button. Saving writes the
    // entry and closes the editor; the connection test runs after it, and its
    // verdict appears on the row.
    @html.div(class="form-row custom-model-save-row", [
      @html.span(class="form-row-status", @settings.text(locale, ProbeHint)),
      @html.button(
        class="button primary compact",
        type_="button",
        disabled=!draft.can_submit(),
        on_click=dispatch(CustomModelSubmit),
        @settings.text(locale, SaveModel),
      ),
      @html.button(
        class="button secondary compact",
        type_="button",
        on_click=dispatch(CustomModelCancel),
        @settings.text(locale, Cancel),
      ),
    ]),
  ]
}
