///|
priv enum DiffMessage {
  AddLineComment
}

///|
fn diff_text(
  language : @localization.Language,
  message : DiffMessage,
) -> String {
  match (language, message) {
    (English, AddLineComment) => "Add line comment"
    (SimplifiedChinese, AddLineComment) => "添加行评论"
    (TraditionalChinese, AddLineComment) => "新增行評論"
    (Japanese, AddLineComment) => "行コメントを追加"
    (Spanish, AddLineComment) => "Añadir comentario de línea"
  }
}
