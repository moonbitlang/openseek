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
