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
    (Spanish, ArchiveMalformed) =>
      "Archivado de Codex: respuesta inválida sobre los cambios del worktree"
    (SimplifiedChinese, ArchiveMalformed) =>
      "Codex 归档失败：工作树更改检查返回了无效响应"
    (TraditionalChinese, ArchiveMalformed) =>
      "Codex 歸檔失敗：工作樹更改檢查返回了無效響應"
    (Japanese, ArchiveMalformed) =>
      "Codex のアーカイブに失敗しました：ワークツリーの変更確認で無効な応答が返されました"
    (English, ArchiveRetained) =>
      "Codex task archived, but its worktree was retained because new local changes appeared during archiving."
    (Spanish, ArchiveRetained) =>
      "La tarea de Codex se archivó, pero se conservó su worktree porque aparecieron nuevos cambios locales durante el archivado."
    (SimplifiedChinese, ArchiveRetained) =>
      "Codex 任务已归档。归档期间出现了新的本地更改，因此保留了工作树。"
    (TraditionalChinese, ArchiveRetained) =>
      "Codex 任務已歸檔。歸檔期間出現了新的本地更改，因此保留了工作樹。"
    (Japanese, ArchiveRetained) =>
      "Codex タスクをアーカイブしました。処理中に新しいローカル変更が発生したため、ワークツリーを保持しました。"
    (English, StatusNotice) => "Codex status"
    (Spanish, StatusNotice) => "Estado de Codex"
    (SimplifiedChinese, StatusNotice) => "Codex 状态"
    (TraditionalChinese, StatusNotice) => "Codex 狀態"
    (Japanese, StatusNotice) => "Codex の状態"
    (English, RequestsNotice) => "Codex requests"
    (Spanish, RequestsNotice) => "Solicitudes de Codex"
    (SimplifiedChinese, RequestsNotice) => "Codex 请求"
    (TraditionalChinese, RequestsNotice) => "Codex 請求"
    (Japanese, RequestsNotice) => "Codex リクエスト"
    (English, AccountNotice) => "Codex account"
    (Spanish, AccountNotice) => "Cuenta de Codex"
    (SimplifiedChinese, AccountNotice) => "Codex 账户"
    (TraditionalChinese, AccountNotice) => "Codex 帳戶"
    (Japanese, AccountNotice) => "Codex アカウント"
    (English, ModelsNotice) => "Codex models"
    (Spanish, ModelsNotice) => "Modelos de Codex"
    (SimplifiedChinese, ModelsNotice) => "Codex 模型"
    (TraditionalChinese, ModelsNotice) => "Codex 模型"
    (Japanese, ModelsNotice) => "Codex モデル"
    (English, ThreadsNotice) => "Codex threads"
    (Spanish, ThreadsNotice) => "Conversaciones de Codex"
    (SimplifiedChinese, ThreadsNotice) => "Codex 对话"
    (TraditionalChinese, ThreadsNotice) => "Codex 對話"
    (Japanese, ThreadsNotice) => "Codex チャット"
    (English, ArchivedNotice) => "Codex archived threads"
    (Spanish, ArchivedNotice) => "Conversaciones archivadas de Codex"
    (SimplifiedChinese, ArchivedNotice) => "Codex 已归档对话"
    (TraditionalChinese, ArchivedNotice) => "Codex 已歸檔對話"
    (Japanese, ArchivedNotice) => "Codex のアーカイブ済みチャット"
    (English, DraftNotice) => "Codex draft"
    (Spanish, DraftNotice) => "Borrador de Codex"
    (SimplifiedChinese, DraftNotice) => "Codex 草稿"
    (TraditionalChinese, DraftNotice) => "Codex 草稿"
    (Japanese, DraftNotice) => "Codex の下書き"
    (English, ThreadNotice) => "Codex thread"
    (Spanish, ThreadNotice) => "Conversación de Codex"
    (SimplifiedChinese, ThreadNotice) => "Codex 对话"
    (TraditionalChinese, ThreadNotice) => "Codex 對話"
    (Japanese, ThreadNotice) => "Codex チャット"
    (English, TurnNotice) => "Codex turn"
    (Spanish, TurnNotice) => "Turno de Codex"
    (SimplifiedChinese, TurnNotice) => "Codex 任务轮次"
    (TraditionalChinese, TurnNotice) => "Codex 任務輪次"
    (Japanese, TurnNotice) => "Codex ターン"
    (English, RepairNotice) => "Codex worktree rebuild"
    (Spanish, RepairNotice) => "Reconstrucción del worktree de Codex"
    (SimplifiedChinese, RepairNotice) => "Codex 工作树重建"
    (TraditionalChinese, RepairNotice) => "Codex 工作樹重建"
    (Japanese, RepairNotice) => "Codex ワークツリーの再作成"
    (English, LoginNotice) => "Codex sign-in"
    (Spanish, LoginNotice) => "Inicio de sesión en Codex"
    (SimplifiedChinese, LoginNotice) => "Codex 登录"
    (TraditionalChinese, LoginNotice) => "Codex 登入"
    (Japanese, LoginNotice) => "Codex ログイン"
    (English, ArchiveNotice) => "Codex archive"
    (Spanish, ArchiveNotice) => "Archivado de Codex"
    (SimplifiedChinese, ArchiveNotice) => "Codex 归档"
    (TraditionalChinese, ArchiveNotice) => "Codex 歸檔"
    (Japanese, ArchiveNotice) => "Codex アーカイブ"
    (English, RestoreNotice) => "Codex restore"
    (Spanish, RestoreNotice) => "Restauración de Codex"
    (SimplifiedChinese, RestoreNotice) => "Codex 恢复"
    (TraditionalChinese, RestoreNotice) => "Codex 恢復"
    (Japanese, RestoreNotice) => "Codex の復元"
    (English, CompactNotice) => "Codex compact"
    (Spanish, CompactNotice) => "Compactación de Codex"
    (SimplifiedChinese, CompactNotice) => "Codex 压缩上下文"
    (TraditionalChinese, CompactNotice) => "Codex 壓縮上下文"
    (Japanese, CompactNotice) => "Codex コンテキストの圧縮"
    (English, ReviewNotice) => "Codex review"
    (Spanish, ReviewNotice) => "Revisión de Codex"
    (SimplifiedChinese, ReviewNotice) => "Codex 审阅"
    (TraditionalChinese, ReviewNotice) => "Codex 審閱"
    (Japanese, ReviewNotice) => "Codex レビュー"
    (English, ResumeNotice) => "Codex resume"
    (Spanish, ResumeNotice) => "Reanudación de Codex"
    (SimplifiedChinese, ResumeNotice) => "Codex 继续任务"
    (TraditionalChinese, ResumeNotice) => "Codex 繼續任務"
    (Japanese, ResumeNotice) => "Codex タスクの続行"
    (English, InterruptNotice) => "Codex interrupt"
    (Spanish, InterruptNotice) => "Interrupción de Codex"
    (SimplifiedChinese, InterruptNotice) => "Codex 中断任务"
    (TraditionalChinese, InterruptNotice) => "Codex 中斷任務"
    (Japanese, InterruptNotice) => "Codex タスクの中断"
    (English, CancelLoginNotice) => "Codex sign-in cancellation"
    (Spanish, CancelLoginNotice) =>
      "Cancelación del inicio de sesión en Codex"
    (SimplifiedChinese, CancelLoginNotice) => "取消 Codex 登录"
    (TraditionalChinese, CancelLoginNotice) => "取消 Codex 登入"
    (Japanese, CancelLoginNotice) => "Codex ログインをキャンセル"
    (English, LogoutNotice) => "Codex sign-out"
    (Spanish, LogoutNotice) => "Cierre de sesión en Codex"
    (SimplifiedChinese, LogoutNotice) => "Codex 退出登录"
    (TraditionalChinese, LogoutNotice) => "Codex 退出登入"
    (Japanese, LogoutNotice) => "Codex ログアウト"
    (English, ApprovalNotice) => "Codex response"
    (Spanish, ApprovalNotice) => "Respuesta de Codex"
    (SimplifiedChinese, ApprovalNotice) => "Codex 响应"
    (TraditionalChinese, ApprovalNotice) => "Codex 響應"
    (Japanese, ApprovalNotice) => "Codex 応答"
  }
}
