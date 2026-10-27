///|
priv enum Message {
  MoonBitGuide
  AdditionalPrompt
  AdditionalPromptDescription
  CustomPrompt
}

///|
fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
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
      "Added to the system prompt for new chats."
    (SimplifiedChinese, AdditionalPromptDescription) =>
      "追加到新对话的系统提示词中。"
    (TraditionalChinese, AdditionalPromptDescription) =>
      "附加至新對話的系統提示詞。"
    (Japanese, AdditionalPromptDescription) =>
      "新しいチャットのシステムプロンプトに追加します。"
    (Spanish, AdditionalPromptDescription) =>
      "Se añade al prompt del sistema de los chats nuevos."
  }
}
