///|
priv enum DynamicMessage {
  DSignInFailure(String)
  DSaved(String)
  DSavedNotOpened(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DSignInFailure(p0)) =>
      "\{p0} You can try signing in again, or download this conversation."
    (Spanish, DSignInFailure(p0)) =>
      "\{p0} Puedes volver a intentar iniciar sesión o descargar esta conversación."
    (SimplifiedChinese, DSignInFailure(p0)) =>
      "\{p0} 你可以重新尝试登录，或下载此对话。"
    (TraditionalChinese, DSignInFailure(p0)) =>
      "\{p0} 你可以重新嘗試登入，或下載此對話。"
    (Japanese, DSignInFailure(p0)) =>
      "\{p0} ログインを再試行するか、このチャットをダウンロードできます。"
    (English, DSaved(p0)) => "Saved to \{p0}."
    (Spanish, DSaved(p0)) => "Guardado en \{p0}."
    (SimplifiedChinese, DSaved(p0)) => "已保存至 \{p0}。"
    (TraditionalChinese, DSaved(p0)) => "已儲存至 \{p0}。"
    (Japanese, DSaved(p0)) => "\{p0} に保存しました。"
    (English, DSavedNotOpened(p0)) =>
      "Saved to \{p0}, but couldn't open it automatically."
    (Spanish, DSavedNotOpened(p0)) =>
      "Guardado en \{p0}, pero no se pudo abrir automáticamente."
    (SimplifiedChinese, DSavedNotOpened(p0)) =>
      "已保存至 \{p0}，但无法自动打开。"
    (TraditionalChinese, DSavedNotOpened(p0)) =>
      "已儲存至 \{p0}，但無法自動開啟。"
    (Japanese, DSavedNotOpened(p0)) =>
      "\{p0} に保存しましたが、自動的に開けませんでした。"
  }
}
