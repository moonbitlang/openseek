///|
priv enum DynamicMessage {
  DFailedExit(String)
  DStopped(String)
  DEnded(String, String)
  DRunningTime(String)
  DHost(String, String)
  DStarted(String)
  DWorkingDirectory(String)
  DLastOutput(String)
  DFailedBecause(String)
  DSpent(String)
  DSpentSteps(String, String)
  DSession(String)
  DWorktree(String, String)
  DWorktreeCommitted(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DFailedExit(p0)) => "Failed · exit \{p0}"
    (Spanish, DFailedExit(p0)) => "Falló · código de salida \{p0}"
    (SimplifiedChinese, DFailedExit(p0)) => "失败 · 退出码 \{p0}"
    (TraditionalChinese, DFailedExit(p0)) => "失敗 · 退出碼 \{p0}"
    (Japanese, DFailedExit(p0)) => "失敗 · 終了コード \{p0}"
    (English, DStopped(p0)) => "Stopped · \{p0}"
    (Spanish, DStopped(p0)) => "Detenido · \{p0}"
    (SimplifiedChinese, DStopped(p0)) => "已停止 · \{p0}"
    (TraditionalChinese, DStopped(p0)) => "已停止 · \{p0}"
    (Japanese, DStopped(p0)) => "停止済み · \{p0}"
    (English, DEnded(p0, p1)) => "Ended \{p0} · Total \{p1}s"
    (Spanish, DEnded(p0, p1)) => "Terminó \{p0} · Total \{p1}s"
    (SimplifiedChinese, DEnded(p0, p1)) => "结束于 \{p0} · 共 \{p1} 秒"
    (TraditionalChinese, DEnded(p0, p1)) => "結束於 \{p0} · 共 \{p1} 秒"
    (Japanese, DEnded(p0, p1)) => "終了：\{p0} · 所要時間 \{p1} 秒"
    (English, DRunningTime(p0)) => "Running for \{p0}s"
    (Spanish, DRunningTime(p0)) => "En ejecución desde hace \{p0}s"
    (SimplifiedChinese, DRunningTime(p0)) => "已运行 \{p0} 秒"
    (TraditionalChinese, DRunningTime(p0)) => "已執行 \{p0} 秒"
    (Japanese, DRunningTime(p0)) => "実行時間 \{p0} 秒"
    (English, DHost(p0, p1)) => "Host: \{p0} · \{p1}"
    (Spanish, DHost(p0, p1)) => "Host: \{p0} · \{p1}"
    (SimplifiedChinese, DHost(p0, p1)) => "主机：\{p0} · \{p1}"
    (TraditionalChinese, DHost(p0, p1)) => "主機：\{p0} · \{p1}"
    (Japanese, DHost(p0, p1)) => "ホスト：\{p0} · \{p1}"
    (English, DStarted(p0)) => "Started \{p0}"
    (Spanish, DStarted(p0)) => "Inicio: \{p0}"
    (SimplifiedChinese, DStarted(p0)) => "开始于 \{p0}"
    (TraditionalChinese, DStarted(p0)) => "開始於 \{p0}"
    (Japanese, DStarted(p0)) => "開始：\{p0}"
    (English, DWorkingDirectory(p0)) => "Working directory: \{p0}"
    (Spanish, DWorkingDirectory(p0)) => "Directorio de trabajo: \{p0}"
    (SimplifiedChinese, DWorkingDirectory(p0)) => "工作目录：\{p0}"
    (TraditionalChinese, DWorkingDirectory(p0)) => "工作目錄：\{p0}"
    (Japanese, DWorkingDirectory(p0)) => "作業ディレクトリ：\{p0}"
    (English, DLastOutput(p0)) => "Last output \{p0}s ago"
    (Spanish, DLastOutput(p0)) => "Última salida hace \{p0}s"
    (SimplifiedChinese, DLastOutput(p0)) => "上次输出在 \{p0} 秒前"
    (TraditionalChinese, DLastOutput(p0)) => "上次輸出在 \{p0} 秒前"
    (Japanese, DLastOutput(p0)) => "最終出力は \{p0} 秒前"
    (English, DFailedBecause(p0)) => "Failed · \{p0}"
    (Spanish, DFailedBecause(p0)) => "Falló · \{p0}"
    (SimplifiedChinese, DFailedBecause(p0)) => "失败 · \{p0}"
    (TraditionalChinese, DFailedBecause(p0)) => "失敗 · \{p0}"
    (Japanese, DFailedBecause(p0)) => "失敗 · \{p0}"
    (English, DSpent(p0)) => "\{p0} tokens"
    (Spanish, DSpent(p0)) => "\{p0} tokens"
    (SimplifiedChinese, DSpent(p0)) => "\{p0} 个 token"
    (TraditionalChinese, DSpent(p0)) => "\{p0} 個 token"
    (Japanese, DSpent(p0)) => "\{p0} トークン"
    (English, DSpentSteps(p0, p1)) => "\{p0} steps · \{p1} tokens"
    (Spanish, DSpentSteps(p0, p1)) => "\{p0} pasos · \{p1} tokens"
    (SimplifiedChinese, DSpentSteps(p0, p1)) => "\{p0} 步 · \{p1} 个 token"
    (TraditionalChinese, DSpentSteps(p0, p1)) => "\{p0} 步 · \{p1} 個 token"
    (Japanese, DSpentSteps(p0, p1)) =>
      "\{p0} ステップ · \{p1} トークン"
    (English, DSession(p0)) => "Session: \{p0}"
    (Spanish, DSession(p0)) => "Sesión: \{p0}"
    (SimplifiedChinese, DSession(p0)) => "会话：\{p0}"
    (TraditionalChinese, DSession(p0)) => "工作階段：\{p0}"
    (Japanese, DSession(p0)) => "セッション：\{p0}"
    (English, DWorktree(p0, p1)) => "Worktree \{p0} · branch \{p1}"
    (Spanish, DWorktree(p0, p1)) => "Worktree \{p0} · rama \{p1}"
    (SimplifiedChinese, DWorktree(p0, p1)) => "工作树 \{p0} · 分支 \{p1}"
    (TraditionalChinese, DWorktree(p0, p1)) => "工作樹 \{p0} · 分支 \{p1}"
    (Japanese, DWorktree(p0, p1)) =>
      "ワークツリー \{p0} · ブランチ \{p1}"
    (English, DWorktreeCommitted(p0)) =>
      "Worktree: committed \{p0} on its branch, ready to take"
    (Spanish, DWorktreeCommitted(p0)) =>
      "Worktree: confirmado \{p0} en su rama, listo para tomar"
    (SimplifiedChinese, DWorktreeCommitted(p0)) =>
      "工作树：已提交 \{p0}（在其分支上），可取回"
    (TraditionalChinese, DWorktreeCommitted(p0)) =>
      "工作樹：已提交 \{p0}（在其分支上），可取回"
    (Japanese, DWorktreeCommitted(p0)) =>
      "ワークツリー：\{p0} をブランチにコミット済み・取り込み可能"
  }
}
