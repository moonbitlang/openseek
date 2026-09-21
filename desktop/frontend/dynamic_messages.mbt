///|
priv enum DynamicMessage {
  DTokens(String)
  DWorktreeArchiveHint(String, String)
  DStorageUnavailable(String)
  DSessionWorkspace(String, String)
  DSession(String)
  DConnecting(String)
  DRestartQuestion(String)
  DDeleteConversation(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DTokens(p0)) => "\{p0} tokens"
    (Spanish, DTokens(p0)) => "\{p0} tokens"
    (SimplifiedChinese, DTokens(p0)) => "\{p0} 个词元"
    (TraditionalChinese, DTokens(p0)) => "\{p0} 個詞元"
    (Japanese, DTokens(p0)) => "\{p0} トークン"
    (English, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\nRuns in worktree \{p1}; archiving removes its checkout but keeps committed work for Repair"
    (Spanish, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\nSe ejecuta en el worktree \{p1}; al archivarlo se elimina la copia de trabajo, pero se conservan los commits para la reparación"
    (SimplifiedChinese, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\n在工作树 \{p1} 中运行；归档会移除检出目录，但保留已提交的更改以供修复"
    (TraditionalChinese, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\n在工作樹 \{p1} 中執行；歸檔會移除檢出目錄，但保留已提交的變更以供修復"
    (Japanese, DWorktreeArchiveHint(p0, p1)) =>
      "\{p0}\nワークツリー \{p1} で実行。アーカイブするとチェックアウトを削除しますが、修復用のコミットは保持されます"
    (English, DStorageUnavailable(p0)) => "Chats storage unavailable: \{p0}"
    (Spanish, DStorageUnavailable(p0)) =>
      "El almacenamiento de conversaciones no está disponible: \{p0}"
    (SimplifiedChinese, DStorageUnavailable(p0)) =>
      "对话存储不可用：\{p0}"
    (TraditionalChinese, DStorageUnavailable(p0)) =>
      "對話儲存不可用：\{p0}"
    (Japanese, DStorageUnavailable(p0)) =>
      "チャットの保存先が利用できません：\{p0}"
    (English, DSessionWorkspace(p0, p1)) => "session \{p0}\nworkspace \{p1}"
    (Spanish, DSessionWorkspace(p0, p1)) =>
      "sesión \{p0}\nespacio de trabajo \{p1}"
    (SimplifiedChinese, DSessionWorkspace(p0, p1)) =>
      "会话 \{p0}\n工作区 \{p1}"
    (TraditionalChinese, DSessionWorkspace(p0, p1)) =>
      "會話 \{p0}\n工作區 \{p1}"
    (Japanese, DSessionWorkspace(p0, p1)) =>
      "セッション \{p0}\nワークスペース \{p1}"
    (English, DSession(p0)) => "session \{p0}"
    (Spanish, DSession(p0)) => "sesión \{p0}"
    (SimplifiedChinese, DSession(p0)) => "会话 \{p0}"
    (TraditionalChinese, DSession(p0)) => "會話 \{p0}"
    (Japanese, DSession(p0)) => "セッション \{p0}"
    (English, DConnecting(p0)) => "Connecting to \{p0}…"
    (Spanish, DConnecting(p0)) => "Conectando con \{p0}…"
    (SimplifiedChinese, DConnecting(p0)) => "正在连接 \{p0}…"
    (TraditionalChinese, DConnecting(p0)) => "正在連線 \{p0}…"
    (Japanese, DConnecting(p0)) => "\{p0} に接続中…"
    (English, DRestartQuestion(p0)) => "Restart into \{p0}?"
    (Spanish, DRestartQuestion(p0)) => "¿Reiniciar en \{p0}?"
    (SimplifiedChinese, DRestartQuestion(p0)) => "重启至 \{p0}？"
    (TraditionalChinese, DRestartQuestion(p0)) => "重啟至 \{p0}？"
    (Japanese, DRestartQuestion(p0)) =>
      "再起動して \{p0} に更新しますか？"
    (English, DDeleteConversation(p0)) =>
      "“\{p0}” and all of its archived subagent history will be permanently deleted. This cannot be undone. Project files and Git branches will remain."
    (Spanish, DDeleteConversation(p0)) =>
      "Se eliminarán de forma permanente «\{p0}» y todo su historial de subagentes archivados. Esta acción no se puede deshacer. Se conservarán los archivos del proyecto y las ramas de Git."
    (SimplifiedChinese, DDeleteConversation(p0)) =>
      "“\{p0}”及其所有已归档的子智能体历史记录将被永久删除，且无法撤销。项目文件和 Git 分支将被保留。"
    (TraditionalChinese, DDeleteConversation(p0)) =>
      "“\{p0}”及其所有已歸檔的子代理程式歷史記錄將被永久刪除，且無法復原。專案檔案和 Git 分支將被保留。"
    (Japanese, DDeleteConversation(p0)) =>
      "「\{p0}」とそのすべてのアーカイブ済みサブエージェント履歴は完全に削除され、元に戻せません。プロジェクトのファイルと Git ブランチは保持されます。"
  }
}
