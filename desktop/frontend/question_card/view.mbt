///|
priv enum Label {
  Heading
  Answer
  Send
  Skip
  Sending
  Next
  PreviousQuestion
  NextQuestion
}

///|
fn label(locale : @i18n.Locale, key : Label) -> String {
  match (locale, key) {
    (SimplifiedChinese, Next) => "下一步"
    (SimplifiedChinese, PreviousQuestion) => "上一题"
    (SimplifiedChinese, NextQuestion) => "下一题"
    (SimplifiedChinese, Heading) => "问题"
    (SimplifiedChinese, Answer) => "或自行撰写回复"
    (SimplifiedChinese, Send) => "发送"
    (SimplifiedChinese, Skip) => "跳过"
    (SimplifiedChinese, Sending) => "正在发送…"
    (TraditionalChinese, Next) => "下一步"
    (TraditionalChinese, PreviousQuestion) => "上一題"
    (TraditionalChinese, NextQuestion) => "下一題"
    (TraditionalChinese, Heading) => "問題"
    (TraditionalChinese, Answer) => "或自行撰寫回覆"
    (TraditionalChinese, Send) => "傳送"
    (TraditionalChinese, Skip) => "略過"
    (TraditionalChinese, Sending) => "正在傳送…"
    (Japanese, Next) => "次へ"
    (Japanese, PreviousQuestion) => "前の質問"
    (Japanese, NextQuestion) => "次の質問"
    (Japanese, Heading) => "質問"
    (Japanese, Answer) => "または返信を入力"
    (Japanese, Send) => "送信"
    (Japanese, Skip) => "スキップ"
    (Japanese, Sending) => "送信中…"
    (Spanish, Next) => "Siguiente"
    (Spanish, PreviousQuestion) => "Pregunta anterior"
    (Spanish, NextQuestion) => "Pregunta siguiente"
    (Spanish, Heading) => "Pregunta"
    (Spanish, Answer) => "O escribe tu respuesta"
    (Spanish, Send) => "Enviar"
    (Spanish, Skip) => "Omitir"
    (Spanish, Sending) => "Enviando…"
    (English, Next) => "Next"
    (English, PreviousQuestion) => "Previous question"
    (English, NextQuestion) => "Next question"
    (English, Heading) => "Question"
    (English, Answer) => "Or write your own reply"
    (English, Send) => "Send"
    (English, Skip) => "Skip"
    (English, Sending) => "Sending…"
  }
}

///|
pub fn Model::view(
  self : Model,
  questions : Array[Question],
  request_id : String,
  locale : @i18n.Locale,
  disabled~ : Bool = false,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let sending = self.is_sending()
  let error = match self.submission {
    Editing(error) => error
    Sending => None
  }
  let disabled = disabled || sending
  let last = self.current == questions.length() - 1
  let answered = questions
    .get(self.current)
    .map_or(false, question => {
      self.answers
      .get(question.id)
      .map_or(false, answer => !answer.text().is_blank())
    })
  let action_disabled = disabled ||
    (if last { !self.complete(questions) } else { !answered })
  let action = emit(
    if last {
      Submit(skip=false)
    } else {
      Navigate(index=self.current + 1)
    },
  )
  let actions = @html.div(class="user-question-actions", [
    @html.button(
      type_="button",
      class="button compact composer-context-action user-question-submit",
      disabled=action_disabled,
      on_click=action,
      label(locale, if sending { Sending } else if last { Send } else { Next }),
    ),
  ])
  let fields = if questions.get(self.current) is Some(question) {
    let draft = self.answers.get(question.id)
    let value = if draft is Some(Written(text)) { text } else { "" }
    let input_id = request_id + "-" + question.id
    [
      @html.fieldset(class="user-question-field", disabled~, [
        @html.legend(class="user-question-title", question.title),
        @html.div(
          class="user-question-options",
          question.options.mapi((index, option) => {
            @html.button(
              type_="button",
              class=if draft is Some(Chosen(selected)) &&
                selected == option.label {
                "user-question-option selected"
              } else {
                "user-question-option"
              },
              attrs=@html.Attrs::build().aria_pressed(
                (draft is Some(Chosen(selected)) && selected == option.label).to_string(),
              ),
              disabled~,
              on_click=emit(Select(question=question.id, option=option.label)),
              [
                @html.span(
                  class="user-question-number",
                  attrs=@html.Attrs::build().aria_hidden("true"),
                  (index + 1).to_string(),
                ),
                @html.span(class="user-question-option-text", [
                  @html.span(option.label),
                  @html.span(
                    class="user-question-option-description",
                    option.description,
                  ),
                ]),
              ],
            )
          }),
        ),
        @html.div(class="user-question-response", [
          @html.div(
            class="user-question-input",
            attrs=@html.Attrs::build().data_set("focus-owner", ""),
            [
              @icons.icon(@icons.icon_edit),
              @html.textarea(
                id=input_id,
                attrs=@html.Attrs::build()
                  .data_set("focus-target", "")
                  .on_keydown(event => {
                    if event.key() == "Enter" &&
                      !event.shift_key() &&
                      !event.is_composing() {
                      event.prevent_default()
                      if action_disabled {
                        @cmd.none
                      } else {
                        action
                      }
                    } else {
                      @cmd.none
                    }
                  }),
                class="user-question-answer",
                rows=1,
                value~,
                disabled~,
                placeholder=label(locale, Answer),
                title=question.title,
                on_input=emit.map(text => Edit(question=question.id, text~)),
                "",
              ),
            ],
          ),
          @html.div(class="user-question-footer", [actions]),
        ]),
      ]),
    ]
  } else {
    []
  }
  @html.div(class="user-question-card", [
    @html.div(class="user-question-header", [
      @html.div(class="user-question-heading", [
        @icons.icon(@icons.icon_question),
        @html.text(label(locale, Heading)),
      ]),
      @html.div(class="user-question-header-actions", [
        @html.div(
          class="user-question-pagination",
          if questions.length() > 1 {
            [
              @html.button(
                type_="button",
                class="icon-button icon-button-compact user-question-previous",
                title=label(locale, PreviousQuestion),
                attrs=@html.Attrs::build().aria_label(
                  label(locale, PreviousQuestion),
                ),
                disabled=disabled || self.current == 0,
                on_click=emit(Navigate(index=self.current - 1)),
                @icons.icon(@icons.icon_chevron_down),
              ),
              @html.span(
                class="user-question-progress",
                "\{self.current + 1} / \{questions.length()}",
              ),
              @html.button(
                type_="button",
                class="icon-button icon-button-compact user-question-next",
                title=label(locale, NextQuestion),
                attrs=@html.Attrs::build().aria_label(
                  label(locale, NextQuestion),
                ),
                disabled=disabled || last,
                on_click=emit(Navigate(index=self.current + 1)),
                @icons.icon(@icons.icon_chevron_down),
              ),
            ]
          } else {
            []
          },
        ),
        @html.button(
          type_="button",
          class="icon-button icon-button-compact user-question-close",
          title=label(locale, Skip),
          attrs=@html.Attrs::build().aria_label(label(locale, Skip)),
          disabled~,
          on_click=emit(Submit(skip=true)),
          @icons.icon(@icons.icon_close),
        ),
      ]),
    ]),
    @html.div(class="user-question-fields", fields),
    @html.div(class="user-question-error", [@html.text(error.unwrap_or(""))]),
  ])
}
