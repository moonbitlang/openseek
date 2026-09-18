///|
priv enum DynamicMessage {
  DTokens(String)
  DWorktreeArchiveHint(String, String)
  DStorageUnavailable(String)
  DSessionWorkspace(String, String)
  DSession(String)
  DConnecting(String)
  DUpdateQuestion(String)
  DDeleteConversation(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DTokens(p0)) => "\{p0} tokens"
    (SimplifiedChinese, DTokens(p0)) => "\{p0} 个词元"
    (Japanese, DTokens(p0)) => "\{p0} トークン"
    (English, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\nRuns in worktree \{p1}; archiving removes its checkout but keeps the branch for Repair"
    (SimplifiedChinese, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\n在工作树 \{p1} 中运行；归档会移除检出目录，但保留分支以供修复"
    (Japanese, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\nワークツリー \{p1} で実行。アーカイブするとチェックアウトを削除しますが、修復用のブランチは保持されます"
    (English, DStorageUnavailable(p0)) => "Chats storage unavailable: \{p0}"
    (SimplifiedChinese, DStorageUnavailable(p0)) =>
      "对话存储不可用：\{p0}"
    (Japanese, DStorageUnavailable(p0)) =>
      "チャットの保存先が利用できません：\{p0}"
    (English, DSessionWorkspace(p0, p1)) => "session \{p0}\nworkspace \{p1}"
    (SimplifiedChinese, DSessionWorkspace(p0, p1)) =>
      "会话 \{p0}\n工作区 \{p1}"
    (Japanese, DSessionWorkspace(p0, p1)) =>
      "セッション \{p0}\nワークスペース \{p1}"
    (English, DSession(p0)) => "session \{p0}"
    (SimplifiedChinese, DSession(p0)) => "会话 \{p0}"
    (Japanese, DSession(p0)) => "セッション \{p0}"
    (English, DConnecting(p0)) => "Connecting to \{p0}…"
    (SimplifiedChinese, DConnecting(p0)) => "正在连接 \{p0}…"
    (Japanese, DConnecting(p0)) => "\{p0} に接続中…"
    (English, DUpdateQuestion(p0)) => "Update to \{p0}?"
    (SimplifiedChinese, DUpdateQuestion(p0)) => "更新至 \{p0}？"
    (Japanese, DUpdateQuestion(p0)) => "\{p0} に更新しますか？"
    (English, DDeleteConversation(p0)) =>
      "“\{p0}” and all of its archived subagent history will be permanently deleted. This cannot be undone. Project files and Git branches will remain."
    (SimplifiedChinese, DDeleteConversation(p0)) =>
      "“\{p0}”及其所有已归档的子智能体历史记录将被永久删除，且无法撤销。项目文件和 Git 分支将被保留。"
    (Japanese, DDeleteConversation(p0)) =>
      "「\{p0}」とそのすべてのアーカイブ済みサブエージェント履歴は完全に削除され、元に戻せません。プロジェクトのファイルと Git ブランチは保持されます。"
  }
}
