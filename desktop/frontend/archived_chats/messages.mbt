// Feature-owned UI messages; all built-in languages are exhaustive.

///|
/// Chrome of the archived-conversations tab; never user-authored titles.
pub(all) enum Message {
  Title
  Description
  ArchivedCount(Int32)
  Filter
  Chats
  Other
  Empty
  NoMatches
  Restore
  Delete
  CloudBadge
  CodexBadge
}

///|
pub fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
    (English, Title) => "Archived chats"
    (Spanish, Title) => "Conversaciones archivadas"
    (SimplifiedChinese, Title) => "已归档对话"
    (TraditionalChinese, Title) => "已歸檔對話"
    (Japanese, Title) => "アーカイブ済みチャット"
    (English, Description) =>
      "Archived conversations stay out of the sidebar. Restore one to continue it, or delete it permanently."
    (Spanish, Description) =>
      "Las conversaciones archivadas no aparecen en la barra lateral. Restaura una para continuarla o elimínala definitivamente."
    (SimplifiedChinese, Description) =>
      "已归档的对话不会出现在侧边栏中。恢复后可以继续对话，也可以永久删除。"
    (TraditionalChinese, Description) =>
      "已歸檔的對話不會出現在側邊欄中。還原後可以繼續對話，也可以永久刪除。"
    (Japanese, Description) =>
      "アーカイブ済みの会話はサイドバーに表示されません。復元すると続きができ、完全に削除することもできます。"
    (English, ArchivedCount(count)) =>
      if count == 1 {
        "1 archived conversation"
      } else {
        "\{count} archived conversations"
      }
    (Spanish, ArchivedCount(count)) =>
      if count == 1 {
        "1 conversación archivada"
      } else {
        "\{count} conversaciones archivadas"
      }
    (SimplifiedChinese, ArchivedCount(count)) => "\{count} 个已归档对话"
    (TraditionalChinese, ArchivedCount(count)) => "\{count} 個已歸檔對話"
    (Japanese, ArchivedCount(count)) =>
      "アーカイブ済みの会話 \{count} 件"
    (English, Filter) => "Filter archived chats"
    (Spanish, Filter) => "Filtrar conversaciones archivadas"
    (SimplifiedChinese, Filter) => "筛选已归档对话"
    (TraditionalChinese, Filter) => "篩選已歸檔對話"
    (Japanese, Filter) => "アーカイブ済みチャットを絞り込む"
    (English, Chats) => "Chats"
    (Spanish, Chats) => "Conversaciones"
    (SimplifiedChinese, Chats) => "对话"
    (TraditionalChinese, Chats) => "對話"
    (Japanese, Chats) => "チャット"
    (English, Other) => "No project"
    (Spanish, Other) => "Sin proyecto"
    (SimplifiedChinese, Other) => "无项目"
    (TraditionalChinese, Other) => "無專案"
    (Japanese, Other) => "プロジェクトなし"
    (English, Empty) => "No archived chats."
    (Spanish, Empty) => "No hay conversaciones archivadas."
    (SimplifiedChinese, Empty) => "没有已归档的对话。"
    (TraditionalChinese, Empty) => "沒有已歸檔的對話。"
    (Japanese, Empty) =>
      "アーカイブ済みのチャットはありません。"
    (English, NoMatches) => "No archived chats match."
    (Spanish, NoMatches) => "Ninguna conversación archivada coincide."
    (SimplifiedChinese, NoMatches) => "没有匹配的已归档对话。"
    (TraditionalChinese, NoMatches) => "沒有符合的已歸檔對話。"
    (Japanese, NoMatches) =>
      "一致するアーカイブ済みチャットはありません。"
    (English, Restore) => "Restore"
    (Spanish, Restore) => "Restaurar"
    (SimplifiedChinese, Restore) => "恢复"
    (TraditionalChinese, Restore) => "還原"
    (Japanese, Restore) => "復元"
    (English, Delete) => "Delete"
    (Spanish, Delete) => "Eliminar"
    (SimplifiedChinese, Delete) => "删除"
    (TraditionalChinese, Delete) => "刪除"
    (Japanese, Delete) => "削除"
    (_, CloudBadge) => "Cloud"
    (_, CodexBadge) => "Codex"
  }
}
