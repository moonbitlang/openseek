///|
priv enum Message {
  MoonBitGuide
  AdditionalPrompt
  AdditionalPromptDescription
  CustomPrompt
  SavePrompt
  UnsavedChanges
  Saving
}

///|
fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
    (English, SavePrompt) => "Save changes"
    (SimplifiedChinese, SavePrompt) => "保存更改"
    (TraditionalChinese, SavePrompt) => "儲存變更"
    (Japanese, SavePrompt) => "変更を保存"
    (Spanish, SavePrompt) => "Guardar cambios"
    (English, UnsavedChanges) => "You have unsaved changes"
    (SimplifiedChinese, UnsavedChanges) => "有未保存的更改"
    (TraditionalChinese, UnsavedChanges) => "有尚未儲存的變更"
    (Japanese, UnsavedChanges) => "未保存の変更があります"
    (Spanish, UnsavedChanges) => "Hay cambios sin guardar"
    (English, Saving) => "Saving…"
    (SimplifiedChinese, Saving) => "正在保存…"
    (TraditionalChinese, Saving) => "儲存中…"
    (Japanese, Saving) => "保存中…"
    (Spanish, Saving) => "Guardando…"
    (English, MoonBitGuide) => "MoonBit guide"
    (SimplifiedChinese, MoonBitGuide) => "MoonBit 指南"
    (TraditionalChinese, MoonBitGuide) => "MoonBit 指南"
    (Japanese, MoonBitGuide) => "MoonBit ガイド"
    (Spanish, MoonBitGuide) => "Guía de MoonBit"
    (English, AdditionalPrompt) => "Additional prompt"
    (SimplifiedChinese, AdditionalPrompt) => "附加提示词"
    (TraditionalChinese, AdditionalPrompt) => "附加提示詞"
    (Japanese, AdditionalPrompt) => "追加プロンプト"
    (Spanish, AdditionalPrompt) => "Instrucciones adicionales"
    (English, CustomPrompt) => "Custom prompt"
    (SimplifiedChinese, CustomPrompt) => "自定义提示词"
    (TraditionalChinese, CustomPrompt) => "自訂提示詞"
    (Japanese, CustomPrompt) => "カスタムプロンプト"
    (Spanish, CustomPrompt) => "Instrucciones personalizadas"
    (English, AdditionalPromptDescription) =>
      "Saved on this host and shared by its clients. Applies to new chats."
    (SimplifiedChinese, AdditionalPromptDescription) =>
      "保存在当前主机，供连接到此主机的客户端共享，仅影响新对话。"
    (TraditionalChinese, AdditionalPromptDescription) =>
      "儲存在目前主機，供連接此主機的用戶端共用，僅套用至新對話。"
    (Japanese, AdditionalPromptDescription) =>
      "このホストに保存し、接続するクライアント間で共有します。新しいチャットに適用します。"
    (Spanish, AdditionalPromptDescription) =>
      "Se guarda en este host y se comparte entre sus clientes. Se aplica a los chats nuevos."
  }
}
