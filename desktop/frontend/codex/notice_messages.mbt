///|
priv enum NoticeMessage {
  ArchiveMalformed
  ArchiveRetained
  StatusNotice
  RequestsNotice
  AccountNotice
  ModelsNotice
  ThreadsNotice
  ArchivedNotice
  DraftNotice
  ThreadNotice
  TurnNotice
  RepairNotice
  LoginNotice
  ArchiveNotice
  RestoreNotice
  CompactNotice
  ReviewNotice
  ResumeNotice
  InterruptNotice
  CancelLoginNotice
  LogoutNotice
  ApprovalNotice
}

///|
fn notice_text(locale : @i18n.Locale, message : NoticeMessage) -> String {
  match (locale, message) {
    (English, ArchiveMalformed) =>
      "Codex archive: malformed dirty-worktree reply"
    (SimplifiedChinese, ArchiveMalformed) =>
      "Codex 归档失败：工作树更改检查返回了无效响应"
    (English, ArchiveRetained) =>
      "Codex task archived, but its worktree was retained because new local changes appeared during archiving."
    (SimplifiedChinese, ArchiveRetained) =>
      "Codex 任务已归档。归档期间出现了新的本地更改，因此保留了工作树。"
    (English, StatusNotice) => "Codex status"
    (SimplifiedChinese, StatusNotice) => "Codex 状态"
    (English, RequestsNotice) => "Codex requests"
    (SimplifiedChinese, RequestsNotice) => "Codex 请求"
    (English, AccountNotice) => "Codex account"
    (SimplifiedChinese, AccountNotice) => "Codex 账户"
    (English, ModelsNotice) => "Codex models"
    (SimplifiedChinese, ModelsNotice) => "Codex 模型"
    (English, ThreadsNotice) => "Codex threads"
    (SimplifiedChinese, ThreadsNotice) => "Codex 对话"
    (English, ArchivedNotice) => "Codex archived threads"
    (SimplifiedChinese, ArchivedNotice) => "Codex 已归档对话"
    (English, DraftNotice) => "Codex draft"
    (SimplifiedChinese, DraftNotice) => "Codex 草稿"
    (English, ThreadNotice) => "Codex thread"
    (SimplifiedChinese, ThreadNotice) => "Codex 对话"
    (English, TurnNotice) => "Codex turn"
    (SimplifiedChinese, TurnNotice) => "Codex 任务轮次"
    (English, RepairNotice) => "Codex worktree rebuild"
    (SimplifiedChinese, RepairNotice) => "Codex 工作树重建"
    (English, LoginNotice) => "Codex sign-in"
    (SimplifiedChinese, LoginNotice) => "Codex 登录"
    (English, ArchiveNotice) => "Codex archive"
    (SimplifiedChinese, ArchiveNotice) => "Codex 归档"
    (English, RestoreNotice) => "Codex restore"
    (SimplifiedChinese, RestoreNotice) => "Codex 恢复"
    (English, CompactNotice) => "Codex compact"
    (SimplifiedChinese, CompactNotice) => "Codex 压缩上下文"
    (English, ReviewNotice) => "Codex review"
    (SimplifiedChinese, ReviewNotice) => "Codex 审阅"
    (English, ResumeNotice) => "Codex resume"
    (SimplifiedChinese, ResumeNotice) => "Codex 继续任务"
    (English, InterruptNotice) => "Codex interrupt"
    (SimplifiedChinese, InterruptNotice) => "Codex 中断任务"
    (English, CancelLoginNotice) => "Codex sign-in cancellation"
    (SimplifiedChinese, CancelLoginNotice) => "取消 Codex 登录"
    (English, LogoutNotice) => "Codex sign-out"
    (SimplifiedChinese, LogoutNotice) => "Codex 退出登录"
    (English, ApprovalNotice) => "Codex response"
    (SimplifiedChinese, ApprovalNotice) => "Codex 响应"
  }
}
