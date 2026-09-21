// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  SubagentRuns(Int)
  RenameLabel
  RenameConversation
  ArchiveLabel
  ArchiveConversation
  StopBeforeArchive
  RestoreLabel
  RestoreConversation
  DeleteLabel
  DeletePermanently
  DeleteUnavailable
  LoadingConversation
  ConversationLoadFailed
  RunningLabel
  NeedsInput
  CompletedUnread
  FailedUnread
  StoppedUnread
  EndedUnread
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, SubagentRuns(1)) => "1 subagent run"
    (Spanish, SubagentRuns(1)) => "1 ejecución de subagente"
    (English, SubagentRuns(count)) => "\{count} subagent runs"
    (Spanish, SubagentRuns(count)) => "\{count} ejecuciones de subagentes"
    (SimplifiedChinese, SubagentRuns(count)) => "\{count} 次子智能体运行"
    (TraditionalChinese, SubagentRuns(count)) =>
      "\{count} 次子代理程式執行"
    (Japanese, SubagentRuns(count)) =>
      "\{count} 件のサブエージェント実行"
    (English, RenameLabel) => "Rename…"
    (Spanish, RenameLabel) => "Cambiar nombre…"
    (SimplifiedChinese, RenameLabel) => "重命名…"
    (TraditionalChinese, RenameLabel) => "重新命名…"
    (Japanese, RenameLabel) => "名前を変更…"
    (English, RenameConversation) => "Rename conversation"
    (Spanish, RenameConversation) => "Cambiar nombre de la conversación"
    (SimplifiedChinese, RenameConversation) => "重命名对话"
    (TraditionalChinese, RenameConversation) => "重新命名對話"
    (Japanese, RenameConversation) => "チャット名を変更"
    (English, ArchiveLabel) => "Archive"
    (Spanish, ArchiveLabel) => "Archivar"
    (SimplifiedChinese, ArchiveLabel) => "归档"
    (TraditionalChinese, ArchiveLabel) => "歸檔"
    (Japanese, ArchiveLabel) => "アーカイブ"
    (English, ArchiveConversation) => "Archive conversation"
    (Spanish, ArchiveConversation) => "Archivar conversación"
    (SimplifiedChinese, ArchiveConversation) => "归档对话"
    (TraditionalChinese, ArchiveConversation) => "歸檔對話"
    (Japanese, ArchiveConversation) => "チャットをアーカイブ"
    (English, StopBeforeArchive) => "Stop this conversation before archiving it"
    (Spanish, StopBeforeArchive) =>
      "Detén esta conversación antes de archivarla"
    (SimplifiedChinese, StopBeforeArchive) => "停止此对话后才能归档"
    (TraditionalChinese, StopBeforeArchive) => "停止此對話後才能歸檔"
    (Japanese, StopBeforeArchive) =>
      "アーカイブするにはこのチャットを停止してください"
    (English, RestoreLabel) => "Restore"
    (Spanish, RestoreLabel) => "Restaurar"
    (SimplifiedChinese, RestoreLabel) => "恢复"
    (TraditionalChinese, RestoreLabel) => "恢復"
    (Japanese, RestoreLabel) => "復元"
    (English, RestoreConversation) => "Restore conversation"
    (Spanish, RestoreConversation) => "Restaurar conversación"
    (SimplifiedChinese, RestoreConversation) => "恢复对话"
    (TraditionalChinese, RestoreConversation) => "恢復對話"
    (Japanese, RestoreConversation) => "チャットを復元"
    (English, DeleteLabel) => "Delete…"
    (Spanish, DeleteLabel) => "Eliminar…"
    (SimplifiedChinese, DeleteLabel) => "删除…"
    (TraditionalChinese, DeleteLabel) => "刪除…"
    (Japanese, DeleteLabel) => "削除…"
    (English, DeletePermanently) => "Permanently delete conversation"
    (Spanish, DeletePermanently) => "Eliminar conversación de forma permanente"
    (SimplifiedChinese, DeletePermanently) => "永久删除对话"
    (TraditionalChinese, DeletePermanently) => "永久刪除對話"
    (Japanese, DeletePermanently) => "チャットを完全に削除"
    (English, DeleteUnavailable) =>
      "Permanent deletion is unavailable for this conversation source"
    (Spanish, DeleteUnavailable) =>
      "La eliminación permanente no está disponible para este origen de conversación"
    (SimplifiedChinese, DeleteUnavailable) =>
      "此对话来源不支持永久删除"
    (TraditionalChinese, DeleteUnavailable) =>
      "此對話來源不支援永久刪除"
    (Japanese, DeleteUnavailable) =>
      "このチャットのソースは完全削除に対応していません"
    (English, LoadingConversation) => "Loading conversation"
    (Spanish, LoadingConversation) => "Cargando conversación"
    (SimplifiedChinese, LoadingConversation) => "正在加载对话"
    (TraditionalChinese, LoadingConversation) => "正在載入對話"
    (Japanese, LoadingConversation) => "チャットを読み込み中"
    (English, ConversationLoadFailed) => "Conversation failed to load"
    (Spanish, ConversationLoadFailed) => "No se pudo cargar la conversación"
    (SimplifiedChinese, ConversationLoadFailed) => "对话加载失败"
    (TraditionalChinese, ConversationLoadFailed) => "對話載入失敗"
    (Japanese, ConversationLoadFailed) =>
      "チャットの読み込みに失敗しました"
    (English, RunningLabel) => "Running"
    (Spanish, RunningLabel) => "En ejecución"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (TraditionalChinese, RunningLabel) => "執行中"
    (Japanese, RunningLabel) => "実行中"
    (English, NeedsInput) => "Needs your input"
    (Spanish, NeedsInput) => "Necesita tu respuesta"
    (SimplifiedChinese, NeedsInput) => "需要你的输入"
    (TraditionalChinese, NeedsInput) => "需要你的輸入"
    (Japanese, NeedsInput) => "入力が必要です"
    (English, CompletedUnread) => "Completed — unread"
    (Spanish, CompletedUnread) => "Completado — sin leer"
    (SimplifiedChinese, CompletedUnread) => "已完成 — 未读"
    (TraditionalChinese, CompletedUnread) => "已完成 — 未讀"
    (Japanese, CompletedUnread) => "完了 — 未読"
    (English, FailedUnread) => "Failed — unread"
    (Spanish, FailedUnread) => "Falló — sin leer"
    (SimplifiedChinese, FailedUnread) => "失败 — 未读"
    (TraditionalChinese, FailedUnread) => "失敗 — 未讀"
    (Japanese, FailedUnread) => "失敗 — 未読"
    (English, StoppedUnread) => "Stopped — unread"
    (Spanish, StoppedUnread) => "Detenido — sin leer"
    (SimplifiedChinese, StoppedUnread) => "已停止 — 未读"
    (TraditionalChinese, StoppedUnread) => "已停止 — 未讀"
    (Japanese, StoppedUnread) => "停止済み — 未読"
    (English, EndedUnread) => "Ended — unread"
    (Spanish, EndedUnread) => "Terminado — sin leer"
    (SimplifiedChinese, EndedUnread) => "已结束 — 未读"
    (TraditionalChinese, EndedUnread) => "已結束 — 未讀"
    (Japanese, EndedUnread) => "終了済み — 未読"
  }
}
