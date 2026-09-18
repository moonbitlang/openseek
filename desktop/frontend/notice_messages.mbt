///|
priv enum NoticeMessage {
  CreateChat(String)
  SaveSettings(String)
  WorkspaceFailure(String)
  SaveWorkspace(String, String)
  ListWorktrees(String, String)
  ArchiveFailure(String)
  DeleteFailure(String)
  ListSessions(String)
  UpdateServer(String)
  UpdateReply(String)
}

///|
fn notice_text(locale : @i18n.Locale, message : NoticeMessage) -> String {
  match (locale, message) {
    (English, CreateChat(p0)) => "Cannot create chat: \{p0}"
    (SimplifiedChinese, CreateChat(p0)) => "无法创建对话：\{p0}"
    (TraditionalChinese, CreateChat(p0)) => "無法建立對話：\{p0}"
    (Japanese, CreateChat(p0)) => "チャットを作成できません：\{p0}"
    (English, SaveSettings(p0)) => "Saving settings failed: \{p0}"
    (SimplifiedChinese, SaveSettings(p0)) => "保存设置失败：\{p0}"
    (TraditionalChinese, SaveSettings(p0)) => "儲存設定失敗：\{p0}"
    (Japanese, SaveSettings(p0)) =>
      "設定を保存できませんでした：\{p0}"
    (English, WorkspaceFailure(p0)) => "Workspace error: \{p0}"
    (SimplifiedChinese, WorkspaceFailure(p0)) => "工作区错误：\{p0}"
    (TraditionalChinese, WorkspaceFailure(p0)) => "工作區錯誤：\{p0}"
    (Japanese, WorkspaceFailure(p0)) => "ワークスペースエラー：\{p0}"
    (English, SaveWorkspace(p0, p1)) =>
      "Workspace settings not saved for \{p0}: \{p1}"
    (SimplifiedChinese, SaveWorkspace(p0, p1)) =>
      "未能保存 \{p0} 的工作区设置：\{p1}"
    (TraditionalChinese, SaveWorkspace(p0, p1)) =>
      "未能儲存 \{p0} 的工作區設定：\{p1}"
    (Japanese, SaveWorkspace(p0, p1)) =>
      "\{p0} のワークスペース設定を保存できませんでした：\{p1}"
    (English, ListWorktrees(p0, p1)) =>
      "Worktree list unavailable for \{p0}: \{p1}"
    (SimplifiedChinese, ListWorktrees(p0, p1)) =>
      "无法获取 \{p0} 的工作树列表：\{p1}"
    (TraditionalChinese, ListWorktrees(p0, p1)) =>
      "無法獲取 \{p0} 的工作樹列表：\{p1}"
    (Japanese, ListWorktrees(p0, p1)) =>
      "\{p0} のワークツリー一覧を取得できません：\{p1}"
    (English, ArchiveFailure(p0)) => "Archive failed: \{p0}"
    (SimplifiedChinese, ArchiveFailure(p0)) => "归档失败：\{p0}"
    (TraditionalChinese, ArchiveFailure(p0)) => "歸檔失敗：\{p0}"
    (Japanese, ArchiveFailure(p0)) =>
      "アーカイブに失敗しました：\{p0}"
    (English, DeleteFailure(p0)) => "Delete failed: \{p0}"
    (SimplifiedChinese, DeleteFailure(p0)) => "删除失败：\{p0}"
    (TraditionalChinese, DeleteFailure(p0)) => "刪除失敗：\{p0}"
    (Japanese, DeleteFailure(p0)) => "削除に失敗しました：\{p0}"
    (English, ListSessions(p0)) => "Session list unavailable: \{p0}"
    (SimplifiedChinese, ListSessions(p0)) => "无法获取会话列表：\{p0}"
    (TraditionalChinese, ListSessions(p0)) => "無法獲取會話列表：\{p0}"
    (Japanese, ListSessions(p0)) =>
      "セッション一覧を取得できません：\{p0}"
    (English, UpdateServer(p0)) => "Could not reach the update server: \{p0}"
    (SimplifiedChinese, UpdateServer(p0)) =>
      "无法连接更新服务器：\{p0}"
    (TraditionalChinese, UpdateServer(p0)) =>
      "無法連線更新伺服器：\{p0}"
    (Japanese, UpdateServer(p0)) =>
      "更新サーバーに接続できません：\{p0}"
    (English, UpdateReply(p0)) => "The update server answered unusably: \{p0}"
    (SimplifiedChinese, UpdateReply(p0)) =>
      "更新服务器返回了无效响应：\{p0}"
    (TraditionalChinese, UpdateReply(p0)) =>
      "更新伺服器返回了無效響應：\{p0}"
    (Japanese, UpdateReply(p0)) =>
      "更新サーバーが無効な応答を返しました：\{p0}"
  }
}
