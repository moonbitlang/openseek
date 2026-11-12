///|
#derive(Eq)
priv enum NoticeMessage {
  SaveSettings(String)
  WorkspaceFailure(String)
  SaveWorkspace(String, String)
  ListWorktrees(String, String)
  ArchiveFailure(String)
  DeleteFailure(String)
  ListSessions(String)
  UpdateServer(String)
  UpdateReply(String)
  LanguageStorageFailure(String)
  RenameFailure(ConversationRenameFailure)
  ReviewSelectionUnavailable
  ReviewSelectionMismatch
  ReviewLoadFailed(String)
}

///|
fn rename_failure_text(
  locale : @i18n.Locale,
  failure : ConversationRenameFailure,
) -> String {
  match (locale, failure) {
    (_, Bridge(problem)) => problem.text(locale)
    (_, Cloud(problem)) => problem.text(locale)
    (English, UnavailableChannel) => "Conversation channel is unavailable"
    (Spanish, UnavailableChannel) =>
      "El canal de la conversación no está disponible"
    (SimplifiedChinese, UnavailableChannel) => "对话连接不可用"
    (TraditionalChinese, UnavailableChannel) => "對話連線不可用"
    (Japanese, UnavailableChannel) =>
      "チャットの接続が利用できません"
    (English, UnavailableWorkspace) => "Conversation workspace is unavailable"
    (Spanish, UnavailableWorkspace) =>
      "El espacio de trabajo de la conversación no está disponible"
    (SimplifiedChinese, UnavailableWorkspace) => "对话工作区不可用"
    (TraditionalChinese, UnavailableWorkspace) => "對話工作區不可用"
    (Japanese, UnavailableWorkspace) =>
      "チャットのワークスペースが利用できません"
    (English, UnsupportedConversation) => "This conversation cannot be renamed"
    (Spanish, UnsupportedConversation) =>
      "No se puede cambiar el nombre de esta conversación"
    (SimplifiedChinese, UnsupportedConversation) => "无法重命名此对话"
    (TraditionalChinese, UnsupportedConversation) =>
      "無法重新命名此對話"
    (Japanese, UnsupportedConversation) =>
      "このチャットの名前を変更できません"
  }
}

///|
fn notice_text(locale : @i18n.Locale, message : NoticeMessage) -> String {
  match (locale, message) {
    (_, LanguageStorageFailure(detail)) =>
      @settings.text(locale, LanguageStorageFailed(detail))
    (English, RenameFailure(failure)) =>
      "Rename failed: \{rename_failure_text(locale, failure)}"
    (Spanish, RenameFailure(failure)) =>
      "No se pudo cambiar el nombre: \{rename_failure_text(locale, failure)}"
    (SimplifiedChinese, RenameFailure(failure)) =>
      "重命名失败：\{rename_failure_text(locale, failure)}"
    (TraditionalChinese, RenameFailure(failure)) =>
      "重新命名失敗：\{rename_failure_text(locale, failure)}"
    (Japanese, RenameFailure(failure)) =>
      "名前を変更できませんでした：\{rename_failure_text(locale, failure)}"
    (English, ReviewSelectionUnavailable) =>
      "This selection belongs to a review that is no longer available. Its saved context is unchanged."
    (Spanish, ReviewSelectionUnavailable) =>
      "Esta selección pertenece a una revisión que ya no está disponible. Su contexto guardado no ha cambiado."
    (SimplifiedChinese, ReviewSelectionUnavailable) =>
      "此选择所属的审阅已不可用。已保存的上下文保持不变。"
    (TraditionalChinese, ReviewSelectionUnavailable) =>
      "此選取範圍所屬的審閱已無法使用。已儲存的內容脈絡保持不變。"
    (Japanese, ReviewSelectionUnavailable) =>
      "この選択範囲のレビューは利用できなくなりました。保存済みのコンテキストは変更されていません。"
    (English, ReviewSelectionMismatch) =>
      "These saved changes no longer match the current review or are hidden by its filters. The saved context is unchanged."
    (Spanish, ReviewSelectionMismatch) =>
      "Estos cambios guardados ya no coinciden con la revisión actual o están ocultos por sus filtros. El contexto guardado no ha cambiado."
    (SimplifiedChinese, ReviewSelectionMismatch) =>
      "这些已保存的更改已不匹配当前审阅，或被其筛选条件隐藏。已保存的上下文保持不变。"
    (TraditionalChinese, ReviewSelectionMismatch) =>
      "這些已儲存的變更已不符合目前的審閱，或已被篩選條件隱藏。已儲存的內容脈絡保持不變。"
    (Japanese, ReviewSelectionMismatch) =>
      "保存済みの変更は現在のレビューと一致しないか、フィルターで非表示になっています。保存済みのコンテキストは変更されていません。"
    (English, ReviewLoadFailed(detail)) =>
      "Unable to load the current review: \{detail}"
    (Spanish, ReviewLoadFailed(detail)) =>
      "No se pudo cargar la revisión actual: \{detail}"
    (SimplifiedChinese, ReviewLoadFailed(detail)) =>
      "无法加载当前审阅：\{detail}"
    (TraditionalChinese, ReviewLoadFailed(detail)) =>
      "無法載入目前的審閱：\{detail}"
    (Japanese, ReviewLoadFailed(detail)) =>
      "現在のレビューを読み込めません：\{detail}"
    (English, SaveSettings(p0)) => "Saving settings failed: \{p0}"
    (Spanish, SaveSettings(p0)) => "No se pudo guardar la configuración: \{p0}"
    (SimplifiedChinese, SaveSettings(p0)) => "保存设置失败：\{p0}"
    (TraditionalChinese, SaveSettings(p0)) => "儲存設定失敗：\{p0}"
    (Japanese, SaveSettings(p0)) =>
      "設定を保存できませんでした：\{p0}"
    (English, WorkspaceFailure(p0)) => "Workspace error: \{p0}"
    (Spanish, WorkspaceFailure(p0)) => "Error del espacio de trabajo: \{p0}"
    (SimplifiedChinese, WorkspaceFailure(p0)) => "工作区错误：\{p0}"
    (TraditionalChinese, WorkspaceFailure(p0)) => "工作區錯誤：\{p0}"
    (Japanese, WorkspaceFailure(p0)) => "ワークスペースエラー：\{p0}"
    (English, SaveWorkspace(p0, p1)) =>
      "Workspace settings not saved for \{p0}: \{p1}"
    (Spanish, SaveWorkspace(p0, p1)) =>
      "No se guardó la configuración del espacio de trabajo de \{p0}: \{p1}"
    (SimplifiedChinese, SaveWorkspace(p0, p1)) =>
      "未能保存 \{p0} 的工作区设置：\{p1}"
    (TraditionalChinese, SaveWorkspace(p0, p1)) =>
      "未能儲存 \{p0} 的工作區設定：\{p1}"
    (Japanese, SaveWorkspace(p0, p1)) =>
      "\{p0} のワークスペース設定を保存できませんでした：\{p1}"
    (English, ListWorktrees(p0, p1)) =>
      "Worktree list unavailable for \{p0}: \{p1}"
    (Spanish, ListWorktrees(p0, p1)) =>
      "Lista de worktrees no disponible para \{p0}: \{p1}"
    (SimplifiedChinese, ListWorktrees(p0, p1)) =>
      "无法获取 \{p0} 的工作树列表：\{p1}"
    (TraditionalChinese, ListWorktrees(p0, p1)) =>
      "無法獲取 \{p0} 的工作樹列表：\{p1}"
    (Japanese, ListWorktrees(p0, p1)) =>
      "\{p0} のワークツリー一覧を取得できません：\{p1}"
    (English, ArchiveFailure(p0)) => "Archive failed: \{p0}"
    (Spanish, ArchiveFailure(p0)) => "No se pudo archivar: \{p0}"
    (SimplifiedChinese, ArchiveFailure(p0)) => "归档失败：\{p0}"
    (TraditionalChinese, ArchiveFailure(p0)) => "歸檔失敗：\{p0}"
    (Japanese, ArchiveFailure(p0)) =>
      "アーカイブに失敗しました：\{p0}"
    (English, DeleteFailure(p0)) => "Delete failed: \{p0}"
    (Spanish, DeleteFailure(p0)) => "No se pudo eliminar: \{p0}"
    (SimplifiedChinese, DeleteFailure(p0)) => "删除失败：\{p0}"
    (TraditionalChinese, DeleteFailure(p0)) => "刪除失敗：\{p0}"
    (Japanese, DeleteFailure(p0)) => "削除に失敗しました：\{p0}"
    (English, ListSessions(p0)) => "Session list unavailable: \{p0}"
    (Spanish, ListSessions(p0)) => "Lista de sesiones no disponible: \{p0}"
    (SimplifiedChinese, ListSessions(p0)) => "无法获取会话列表：\{p0}"
    (TraditionalChinese, ListSessions(p0)) => "無法獲取會話列表：\{p0}"
    (Japanese, ListSessions(p0)) =>
      "セッション一覧を取得できません：\{p0}"
    (English, UpdateServer(p0)) => "Could not reach the update server: \{p0}"
    (Spanish, UpdateServer(p0)) =>
      "No se pudo conectar con el servidor de actualizaciones: \{p0}"
    (SimplifiedChinese, UpdateServer(p0)) =>
      "无法连接更新服务器：\{p0}"
    (TraditionalChinese, UpdateServer(p0)) =>
      "無法連線更新伺服器：\{p0}"
    (Japanese, UpdateServer(p0)) =>
      "更新サーバーに接続できません：\{p0}"
    (English, UpdateReply(p0)) => "The update server answered unusably: \{p0}"
    (Spanish, UpdateReply(p0)) =>
      "El servidor de actualizaciones devolvió una respuesta no válida: \{p0}"
    (SimplifiedChinese, UpdateReply(p0)) =>
      "更新服务器返回了无效响应：\{p0}"
    (TraditionalChinese, UpdateReply(p0)) =>
      "更新伺服器返回了無效響應：\{p0}"
    (Japanese, UpdateReply(p0)) =>
      "更新サーバーが無効な応答を返しました：\{p0}"
  }
}
