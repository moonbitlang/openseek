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
    (English, SaveSettings(p0)) => "Saving settings failed: \{p0}"
    (SimplifiedChinese, SaveSettings(p0)) => "保存设置失败：\{p0}"
    (English, WorkspaceFailure(p0)) => "Workspace error: \{p0}"
    (SimplifiedChinese, WorkspaceFailure(p0)) => "工作区错误：\{p0}"
    (English, SaveWorkspace(p0, p1)) =>
      "Workspace settings not saved for \{p0}: \{p1}"
    (SimplifiedChinese, SaveWorkspace(p0, p1)) =>
      "未能保存 \{p0} 的工作区设置：\{p1}"
    (English, ListWorktrees(p0, p1)) =>
      "Worktree list unavailable for \{p0}: \{p1}"
    (SimplifiedChinese, ListWorktrees(p0, p1)) =>
      "无法获取 \{p0} 的工作树列表：\{p1}"
    (English, ArchiveFailure(p0)) => "Archive failed: \{p0}"
    (SimplifiedChinese, ArchiveFailure(p0)) => "归档失败：\{p0}"
    (English, DeleteFailure(p0)) => "Delete failed: \{p0}"
    (SimplifiedChinese, DeleteFailure(p0)) => "删除失败：\{p0}"
    (English, ListSessions(p0)) => "Session list unavailable: \{p0}"
    (SimplifiedChinese, ListSessions(p0)) => "无法获取会话列表：\{p0}"
    (English, UpdateServer(p0)) => "Could not reach the update server: \{p0}"
    (SimplifiedChinese, UpdateServer(p0)) =>
      "无法连接更新服务器：\{p0}"
    (English, UpdateReply(p0)) => "The update server answered unusably: \{p0}"
    (SimplifiedChinese, UpdateReply(p0)) =>
      "更新服务器返回了无效响应：\{p0}"
  }
}
