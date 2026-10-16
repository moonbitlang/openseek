///|
fn message_context_view(
  locale~ : @i18n.Locale,
  context : @message_context.Context,
) -> @html.Html {
  let (label, identity, text) = match context {
    Message(source_session~, message_id=_, text~) => {
      let label = match locale {
        English => "Message from another conversation"
        SimplifiedChinese => "来自另一对话的消息"
        TraditionalChinese => "來自另一對話的訊息"
        Japanese => "別の会話からのメッセージ"
        Spanish => "Mensaje de otra conversación"
      }
      (label, source_session, text)
    }
    DeliveryResult(target~, status~, error~, ..) => {
      let label = match (locale, status) {
        (English, "sent") => "Message sent"
        (SimplifiedChinese, "sent") => "消息已发送"
        (TraditionalChinese, "sent") => "訊息已傳送"
        (Japanese, "sent") => "メッセージを送信しました"
        (Spanish, "sent") => "Mensaje enviado"
        (English, "rejected" | "cancelled") => "Message cancelled"
        (SimplifiedChinese, "rejected" | "cancelled") => "消息已取消"
        (TraditionalChinese, "rejected" | "cancelled") => "訊息已取消"
        (Japanese, "rejected" | "cancelled") =>
          "メッセージをキャンセルしました"
        (Spanish, "rejected" | "cancelled") => "Mensaje cancelado"
        (English, _) => "Message not sent"
        (SimplifiedChinese, _) => "消息未发送"
        (TraditionalChinese, _) => "訊息未傳送"
        (Japanese, _) => "メッセージは送信されませんでした"
        (Spanish, _) => "Mensaje no enviado"
      }
      (label, target, error.unwrap_or(""))
    }
    UserQuestionResponse(request_id~, questions~, answers~) =>
      return question_response_view(locale~, request_id, questions, answers)
  }
  @html.div(
    class="session-message",
    [
      @html.div(class="session-message-source", title=identity, label),
      ..if text.is_empty() {
        []
      } else {
        [@html.div(class="msg-content", inline_code_nodes(text))]
      },
    ],
  )
}

///|
fn question_response_view(
  locale~ : @i18n.Locale,
  request_id : String,
  questions : Array[@protocol.UserQuestion],
  answers : Map[String, String]?,
) -> @html.Html {
  let label = match (locale, answers) {
    (English, None) => "Questions skipped"
    (SimplifiedChinese, None) => "已跳过提问"
    (TraditionalChinese, None) => "已略過提問"
    (Japanese, None) => "質問をスキップしました"
    (Spanish, None) => "Preguntas omitidas"
    (English, Some(_)) => "Your answers"
    (SimplifiedChinese, Some(_)) => "你的回答"
    (TraditionalChinese, Some(_)) => "你的回答"
    (Japanese, Some(_)) => "あなたの回答"
    (Spanish, Some(_)) => "Tus respuestas"
  }
  let children = [
    @html.div(class="session-message-source", title=request_id, label),
  ]
  if answers is Some(answers) {
    for question in questions {
      if answers.get(question.id) is Some(answer) {
        children.push(
          @html.div(class="question-response-item", [
            @html.div(class="question-response-title", question.title),
            @html.div(class="msg-content", answer),
          ]),
        )
      }
    }
  }
  @html.div(class="session-message transcript-question-response", children)
}
