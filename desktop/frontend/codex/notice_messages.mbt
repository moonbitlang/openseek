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
    (Japanese, ArchiveMalformed) =>
      "Codex のアーカイブに失敗しました：ワークツリーの変更確認で無効な応答が返されました"
    (English, ArchiveRetained) =>
      "Codex task archived, but its worktree was retained because new local changes appeared during archiving."
    (SimplifiedChinese, ArchiveRetained) =>
      "Codex 任务已归档。归档期间出现了新的本地更改，因此保留了工作树。"
    (Japanese, ArchiveRetained) =>
      "Codex タスクをアーカイブしました。処理中に新しいローカル変更が発生したため、ワークツリーを保持しました。"
    (English, StatusNotice) => "Codex status"
    (SimplifiedChinese, StatusNotice) => "Codex 状态"
    (Japanese, StatusNotice) => "Codex の状態"
    (English, RequestsNotice) => "Codex requests"
    (SimplifiedChinese, RequestsNotice) => "Codex 请求"
    (Japanese, RequestsNotice) => "Codex リクエスト"
    (English, AccountNotice) => "Codex account"
    (SimplifiedChinese, AccountNotice) => "Codex 账户"
    (Japanese, AccountNotice) => "Codex アカウント"
    (English, ModelsNotice) => "Codex models"
    (SimplifiedChinese, ModelsNotice) => "Codex 模型"
    (Japanese, ModelsNotice) => "Codex モデル"
    (English, ThreadsNotice) => "Codex threads"
    (SimplifiedChinese, ThreadsNotice) => "Codex 对话"
    (Japanese, ThreadsNotice) => "Codex チャット"
    (English, ArchivedNotice) => "Codex archived threads"
    (SimplifiedChinese, ArchivedNotice) => "Codex 已归档对话"
    (Japanese, ArchivedNotice) => "Codex のアーカイブ済みチャット"
    (English, DraftNotice) => "Codex draft"
    (SimplifiedChinese, DraftNotice) => "Codex 草稿"
    (Japanese, DraftNotice) => "Codex の下書き"
    (English, ThreadNotice) => "Codex thread"
    (SimplifiedChinese, ThreadNotice) => "Codex 对话"
    (Japanese, ThreadNotice) => "Codex チャット"
    (English, TurnNotice) => "Codex turn"
    (SimplifiedChinese, TurnNotice) => "Codex 任务轮次"
    (Japanese, TurnNotice) => "Codex ターン"
    (English, RepairNotice) => "Codex worktree rebuild"
    (SimplifiedChinese, RepairNotice) => "Codex 工作树重建"
    (Japanese, RepairNotice) => "Codex ワークツリーの再作成"
    (English, LoginNotice) => "Codex sign-in"
    (SimplifiedChinese, LoginNotice) => "Codex 登录"
    (Japanese, LoginNotice) => "Codex ログイン"
    (English, ArchiveNotice) => "Codex archive"
    (SimplifiedChinese, ArchiveNotice) => "Codex 归档"
    (Japanese, ArchiveNotice) => "Codex アーカイブ"
    (English, RestoreNotice) => "Codex restore"
    (SimplifiedChinese, RestoreNotice) => "Codex 恢复"
    (Japanese, RestoreNotice) => "Codex の復元"
    (English, CompactNotice) => "Codex compact"
    (SimplifiedChinese, CompactNotice) => "Codex 压缩上下文"
    (Japanese, CompactNotice) => "Codex コンテキストの圧縮"
    (English, ReviewNotice) => "Codex review"
    (SimplifiedChinese, ReviewNotice) => "Codex 审阅"
    (Japanese, ReviewNotice) => "Codex レビュー"
    (English, ResumeNotice) => "Codex resume"
    (SimplifiedChinese, ResumeNotice) => "Codex 继续任务"
    (Japanese, ResumeNotice) => "Codex タスクの続行"
    (English, InterruptNotice) => "Codex interrupt"
    (SimplifiedChinese, InterruptNotice) => "Codex 中断任务"
    (Japanese, InterruptNotice) => "Codex タスクの中断"
    (English, CancelLoginNotice) => "Codex sign-in cancellation"
    (SimplifiedChinese, CancelLoginNotice) => "取消 Codex 登录"
    (Japanese, CancelLoginNotice) => "Codex ログインをキャンセル"
    (English, LogoutNotice) => "Codex sign-out"
    (SimplifiedChinese, LogoutNotice) => "Codex 退出登录"
    (Japanese, LogoutNotice) => "Codex ログアウト"
    (English, ApprovalNotice) => "Codex response"
    (SimplifiedChinese, ApprovalNotice) => "Codex 响应"
    (Japanese, ApprovalNotice) => "Codex 応答"
  }
}
