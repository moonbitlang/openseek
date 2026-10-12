///|
/// Keep the wrapper mounted so selection updates cannot replace imperative
/// document hosts. This is a nonmodal card; users can adjust the selection.
fn office_selection_preview_view(
  locale : @i18n.Locale,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let preview = state.pending_office_selection(ctx)
  let content = match preview {
    None => []
    Some(preview) =>
      [
        @html.div(
          class="office-selection-question",
          ui(locale, OfficeSelectionQuestion),
        ),
        @html.div(
          class="office-selection-source",
          title=preview.summary.file,
          preview.summary.heading(),
        ),
        @html.div(
          class="office-selection-excerpt",
          if preview.summary.text.trim().is_empty() {
            ui(locale, EmptySelection)
          } else {
            preview.summary.text
          },
        ),
        @html.div(class="office-selection-actions", [
          @html.button(
            type_="button",
            class="office-selection-cancel",
            attrs=@html.Attrs::build().on_mousedown(event => {
              event.prevent_default()
              @cmd.none
            }),
            on_click=dispatch(OfficeSelectionDismissed(preview)),
            ui(locale, CancelSelection),
          ),
          @html.button(
            type_="button",
            class="office-selection-add",
            attrs=@html.Attrs::build().on_mousedown(event => {
              event.prevent_default()
              @cmd.none
            }),
            on_click=dispatch(OfficeSelectionConfirmed(preview)),
            ui(locale, AddToContext),
          ),
        ]),
      ]
  }
  @html.div(
    class=if preview is Some(_) {
      "office-selection-preview"
    } else {
      "office-selection-preview hidden"
    },
    attrs=@html.Attrs::build()
      .role("group")
      .aria_label(ui(locale, OfficeSelectionQuestion))
      .on_keydown(event => {
        if event.key() == "Escape" && preview is Some(preview) {
          event.prevent_default()
          event.stop_propagation()
          dispatch(OfficeSelectionDismissed(preview))
        } else {
          @cmd.none
        }
      }),
    [@html.div(id=OfficeFeedbackHostId, ([] : Array[@html.Html])), ..content],
  )
}
