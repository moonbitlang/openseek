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
    (English, SubagentRuns(count)) => "\{count} subagent runs"
    (SimplifiedChinese, SubagentRuns(count)) => "\{count} 次子智能体运行"
    (English, RenameLabel) => "Rename…"
    (SimplifiedChinese, RenameLabel) => "重命名…"
    (English, RenameConversation) => "Rename conversation"
    (SimplifiedChinese, RenameConversation) => "重命名对话"
    (English, ArchiveLabel) => "Archive"
    (SimplifiedChinese, ArchiveLabel) => "归档"
    (English, ArchiveConversation) => "Archive conversation"
    (SimplifiedChinese, ArchiveConversation) => "归档对话"
    (English, StopBeforeArchive) => "Stop this conversation before archiving it"
    (SimplifiedChinese, StopBeforeArchive) => "停止此对话后才能归档"
    (English, RestoreLabel) => "Restore"
    (SimplifiedChinese, RestoreLabel) => "恢复"
    (English, RestoreConversation) => "Restore conversation"
    (SimplifiedChinese, RestoreConversation) => "恢复对话"
    (English, DeleteLabel) => "Delete…"
    (SimplifiedChinese, DeleteLabel) => "删除…"
    (English, DeletePermanently) => "Permanently delete conversation"
    (SimplifiedChinese, DeletePermanently) => "永久删除对话"
    (English, DeleteUnavailable) =>
      "Permanent deletion is unavailable for this conversation source"
    (SimplifiedChinese, DeleteUnavailable) =>
      "此对话来源不支持永久删除"
    (English, LoadingConversation) => "Loading conversation"
    (SimplifiedChinese, LoadingConversation) => "正在加载对话"
    (English, ConversationLoadFailed) => "Conversation failed to load"
    (SimplifiedChinese, ConversationLoadFailed) => "对话加载失败"
    (English, RunningLabel) => "Running"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (English, NeedsInput) => "Needs your input"
    (SimplifiedChinese, NeedsInput) => "需要你的输入"
    (English, CompletedUnread) => "Completed — unread"
    (SimplifiedChinese, CompletedUnread) => "已完成 — 未读"
    (English, FailedUnread) => "Failed — unread"
    (SimplifiedChinese, FailedUnread) => "失败 — 未读"
    (English, StoppedUnread) => "Stopped — unread"
    (SimplifiedChinese, StoppedUnread) => "已停止 — 未读"
    (English, EndedUnread) => "Ended — unread"
    (SimplifiedChinese, EndedUnread) => "已结束 — 未读"
  }
}
