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
/// and the actions that own it. Each row owns its connection test, because
/// each entry names its own endpoint and key; the endpoint above the list is
/// only the fallback, so nothing here repeats it.
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
  @ui.form_row(
    entry.display_name(),
    [
      connection_probe_status_line(model, model_id=Some(entry.id)),
      connection_test_button(dispatch, model, model_id=Some(entry.id)),
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
/// The editor for the draft the page holds: the fields that name the model
/// and its context window, then the row that saves it.
fn custom_model_editor_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let locale = model.locale
  guard model.custom_model is Some(draft) else { return [] }
  let existing = model.custom_models()
  let field = (
    value : String,
    placeholder : String,
    label : @settings.Message,
    on_input : @cmd.Emit[String],
    invalid : Bool,
  ) => {
    @html.input(
      class="setting-input field-surface",
      input_type=@html.InputType::Text,
      value~,
      placeholder~,
      on_input~,
      attrs=@html.Attrs::build()
        .aria_label(@settings.text(locale, label))
        .aria_invalid(if invalid { "true" } else { "false" })
        .data_set("focus-owner", ""),
    )
  }
  let rename_warning = match draft.original {
    Some(original) if draft.id.trim().to_owned() != original &&
      !draft.id.trim().is_empty() =>
      match model.custom_model_session_count(original) {
        0 => None
        used => Some(@settings.text(locale, RenameModelInUse(used)))
      }
    _ => None
  }
  let id_error = draft.id_error(existing)
  [
    @ui.form_row(
      @settings.text(locale, ModelId),
      [
        field(
          draft.id,
          "gemini-4-hydrogen",
          ModelId,
          dispatch.map(value => CustomModelIdChanged(value)),
          id_error is Some(_),
        ),
      ],
      desc=match id_error {
        Some(err) => @settings.text(locale, err)
        None =>
          match rename_warning {
            Some(warning) => warning
            None => @settings.text(locale, ModelIdHint)
          }
      },
      desc_invalid=id_error is Some(_),
    ),
    @ui.form_row(
      @settings.text(locale, ModelName),
      [
        field(
          draft.label,
          "Gemini 4 Hydrogen",
          ModelName,
          dispatch.map(value => CustomModelLabelChanged(value)),
          !draft.label_ok(),
        ),
        @html.span("\{draft.label.trim().length()}/64"),
      ],
      desc=if draft.label_ok() {
        @settings.text(locale, ModelNameHint)
      } else {
        @settings.text(locale, ModelNameTooLong)
      },
      desc_invalid=!draft.label_ok(),
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
          !draft.window_ok(),
        ),
      ],
      desc=if draft.window_ok() {
        @settings.text(locale, ModelContextWindowHint)
      } else {
        @settings.text(locale, ModelContextWindowInvalid)
      },
      desc_invalid=!draft.window_ok(),
    ),
    @html.div(class="form-row custom-model-save-row", [
      @html.button(
        class="button primary compact",
        type_="button",
        disabled=!draft.can_submit(existing),
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
