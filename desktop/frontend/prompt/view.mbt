///|
/// Render the preference editor. The host supplies its shared menu controls;
/// selection, text editing, persistence, and prompt resolution stay here.
pub fn Model::view(
  self : Model,
  locale : @i18n.Locale,
  dispatch : @cmd.Emit[Msg],
  ready~ : Bool,
  saving~ : Bool,
  open~ : Bool,
  toggle~ : @cmd.Cmd,
  dismiss~ : @cmd.Cmd,
) -> Array[@html.Html] {
  [
    @settings.row(
      text(locale, AdditionalPrompt),
      [
        @select_control.Control(
          id="prompt-choice",
          groups=[
            {
              label: text(locale, AdditionalPrompt),
              options: [
                @select_control.ViewOption(
                  value="builtin_moonbit_guide",
                  label=text(locale, MoonBitGuide),
                ),
                @select_control.ViewOption(
                  value="custom",
                  label=text(locale, CustomPrompt),
                ),
              ],
            },
          ],
          selected=match self.source {
            Builtin => "builtin_moonbit_guide"
            Custom => "custom"
          },
          disabled=!ready || saving,
          open~,
          toggle~,
          dismiss~,
          change=@cmd.Emit(value => {
            @cmd.batch([dispatch(Selected(value)), dismiss])
          }),
          title=text(locale, AdditionalPrompt),
          aria_label=text(locale, AdditionalPrompt),
          presentation=Setting,
        ).render(),
      ],
      desc=text(locale, AdditionalPromptDescription),
    ),
    ..if self.source is Custom {
      [
        @settings.row(
          text(locale, CustomPrompt),
          [
            @html.textarea(
              value=self.draft.unwrap_or(self.custom_text),
              disabled=!ready || saving,
              rows=6,
              on_input=dispatch.map(text => Edited(text)),
              attrs=@html.Attrs::build()
                .aria_label(text(locale, CustomPrompt))
                .data_set("focus-owner", ""),
              "",
            ),
            @html.div(class="prompt-save-bar", [
              @html.span(
                class="prompt-save-status",
                attrs=@html.Attrs::build().role("status"),
                if self.draft is Some(_) && !saving {
                  text(locale, UnsavedChanges)
                } else {
                  ""
                },
              ),
              @html.button(
                class="button primary",
                type_="button",
                disabled=!ready || saving || self.draft is None,
                on_click=dispatch(Save),
                text(locale, if saving { Saving } else { SavePrompt }),
              ),
            ]),
          ],
          stack=true,
        ),
      ]
    },
  ]
}
