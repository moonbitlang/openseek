// The custom-model section of the API page: stored entries with edit/delete
// actions and an inline editor.

///|
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
    rows.push(
      @ui.form_row("", [
        @html.button(
          class="button secondary compact",
          type_="button",
          on_click=dispatch(CustomModel(Add)),
          @settings.text(locale, AddModel),
        ),
      ]),
    )
  }
  rows
}

///|
fn custom_model_entry_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  entry : @protocol.CustomModel,
) -> @html.Html {
  let locale = model.locale
  @ui.form_row(
    custom_model_display_name(entry),
    [
      @html.button(
        class="button secondary compact",
        type_="button",
        on_click=dispatch(CustomModel(Edit(entry.id))),
        @settings.text(locale, EditModel),
      ),
      @html.button(
        class="button danger compact",
        type_="button",
        on_click=dispatch(CustomModel(Delete(entry.id))),
        @settings.text(locale, DeleteModel),
      ),
    ],
    desc=entry.id,
  )
}

///|
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
  let id_error = draft.id_error(existing)
  [
    @ui.form_row(
      @settings.text(locale, ModelId),
      [
        field(
          draft.id,
          "gemini-4-hydrogen",
          ModelId,
          dispatch.map(value => CustomModel(IdChanged(value))),
          id_error is Some(_),
        ),
      ],
      desc=match id_error {
        Some(err) => @settings.text(locale, err)
        None => @settings.text(locale, ModelIdHint)
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
          dispatch.map(value => CustomModel(LabelChanged(value))),
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
    @ui.form_row(
      @settings.text(locale, ModelContextWindow),
      [
        field(
          draft.window,
          "1000000",
          ModelContextWindow,
          dispatch.map(value => CustomModel(WindowChanged(value))),
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
        on_click=dispatch(CustomModel(Submit)),
        @settings.text(locale, SaveModel),
      ),
      @html.button(
        class="button secondary compact",
        type_="button",
        on_click=dispatch(CustomModel(Cancel)),
        @settings.text(locale, Cancel),
      ),
    ]),
  ]
}
