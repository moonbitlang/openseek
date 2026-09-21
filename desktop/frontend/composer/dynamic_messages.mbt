///|
priv enum DynamicMessage {
  DJump(String)
  DSettingGoal(String)
  DGoalBlocked(String)
  DGoalBlockedDetails(String, String)
  DGoal(String)
  DWorktree(String)
  DMissingWorktree(String)
  DRebuildWorktree(String)
  DArchiveMissing(String)
  DArchiveLabel(String)
  DReconnecting(String)
  DArchiveWarning(String, String)
  DArchiveQuestion(String)
  DWorkingStep(String)
  DRetry(String, String, String)
  DFailedChecks(String)
  DPendingChecks(String)
  DPassedChecks(String)
  DFileCount(String)
  DOnBranch(String)
  DFromBranch(String)
  DRule(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DJump(p0)) => "Jump to \{p0}"
    (Spanish, DJump(p0)) => "Ir a \{p0}"
    (SimplifiedChinese, DJump(p0)) => "跳转至 \{p0}"
    (TraditionalChinese, DJump(p0)) => "跳轉至 \{p0}"
    (Japanese, DJump(p0)) => "\{p0} へ移動"
    (English, DSettingGoal(p0)) => "Setting goal: \{p0}"
    (Spanish, DSettingGoal(p0)) => "Estableciendo objetivo: \{p0}"
    (SimplifiedChinese, DSettingGoal(p0)) => "正在设置目标：\{p0}"
    (TraditionalChinese, DSettingGoal(p0)) => "正在設定目標：\{p0}"
    (Japanese, DSettingGoal(p0)) => "目標を設定中：\{p0}"
    (English, DGoalBlocked(p0)) => "Goal blocked: \{p0}"
    (Spanish, DGoalBlocked(p0)) => "Objetivo bloqueado: \{p0}"
    (SimplifiedChinese, DGoalBlocked(p0)) => "目标受阻：\{p0}"
    (TraditionalChinese, DGoalBlocked(p0)) => "目標受阻：\{p0}"
    (Japanese, DGoalBlocked(p0)) =>
      "目標の進行が阻まれています：\{p0}"
    (English, DGoalBlockedDetails(p0, p1)) => "Goal: \{p0}\n\nBlocked: \{p1}"
    (Spanish, DGoalBlockedDetails(p0, p1)) =>
      "Objetivo: \{p0}\n\nBloqueado: \{p1}"
    (SimplifiedChinese, DGoalBlockedDetails(p0, p1)) =>
      "目标：\{p0}\n\n受阻原因：\{p1}"
    (TraditionalChinese, DGoalBlockedDetails(p0, p1)) =>
      "目標：\{p0}\n\n受阻原因：\{p1}"
    (Japanese, DGoalBlockedDetails(p0, p1)) =>
      "目標：\{p0}\n\n阻害要因：\{p1}"
    (English, DGoal(p0)) => "Goal: \{p0}"
    (Spanish, DGoal(p0)) => "Objetivo: \{p0}"
    (SimplifiedChinese, DGoal(p0)) => "目标：\{p0}"
    (TraditionalChinese, DGoal(p0)) => "目標：\{p0}"
    (Japanese, DGoal(p0)) => "目標：\{p0}"
    (English, DWorktree(p0)) => "This chat runs in worktree \{p0}"
    (Spanish, DWorktree(p0)) =>
      "Esta conversación se ejecuta en el worktree \{p0}"
    (SimplifiedChinese, DWorktree(p0)) =>
      "此对话在工作树 \{p0} 中运行"
    (TraditionalChinese, DWorktree(p0)) =>
      "此對話在工作樹 \{p0} 中執行"
    (Japanese, DWorktree(p0)) =>
      "このチャットはワークツリー \{p0} で実行されます"
    (English, DMissingWorktree(p0)) =>
      "Worktree \{p0} has no checkout. Restore the commit last saved by OpenSeek to continue."
    (Spanish, DMissingWorktree(p0)) =>
      "El worktree \{p0} no tiene una copia de trabajo. Restaura el último commit guardado por OpenSeek para continuar."
    (SimplifiedChinese, DMissingWorktree(p0)) =>
      "工作树 \{p0} 缺少检出目录。恢复到 OpenSeek 上次保存的提交后即可继续。"
    (TraditionalChinese, DMissingWorktree(p0)) =>
      "工作樹 \{p0} 缺少檢出目錄。恢復到 OpenSeek 上次儲存的提交後即可繼續。"
    (Japanese, DMissingWorktree(p0)) =>
      "ワークツリー \{p0} のチェックアウトがありません。OpenSeek が最後に保存したコミットを復元すると続行できます。"
    (English, DRebuildWorktree(p0)) =>
      "Restore the last saved commit at .worktrees/\{p0}"
    (Spanish, DRebuildWorktree(p0)) =>
      "Restaurar el último commit guardado en .worktrees/\{p0}"
    (SimplifiedChinese, DRebuildWorktree(p0)) =>
      "将上次保存的提交恢复到 .worktrees/\{p0}"
    (TraditionalChinese, DRebuildWorktree(p0)) =>
      "將上次儲存的提交恢復到 .worktrees/\{p0}"
    (Japanese, DRebuildWorktree(p0)) =>
      "最後に保存したコミットを .worktrees/\{p0} に復元"
    (English, DArchiveMissing(p0)) =>
      "Archive this \{p0} without rebuilding its worktree"
    (Spanish, DArchiveMissing(_)) =>
      "Archivar esta conversación sin reconstruir su worktree"
    (SimplifiedChinese, DArchiveMissing(_)) =>
      "直接归档此对话，不重建工作树"
    (TraditionalChinese, DArchiveMissing(_)) =>
      "直接歸檔此對話，不重建工作樹"
    (Japanese, DArchiveMissing(_)) =>
      "ワークツリーを再作成せず、このチャットをアーカイブ"
    (English, DArchiveLabel(p0)) => "Archive \{p0}"
    (Spanish, DArchiveLabel(_)) => "Archivar conversación"
    (SimplifiedChinese, DArchiveLabel(_)) => "归档对话"
    (TraditionalChinese, DArchiveLabel(_)) => "歸檔對話"
    (Japanese, DArchiveLabel(_)) => "チャットをアーカイブ"
    (English, DReconnecting(p0)) => "Can't reach \{p0} — reconnecting…"
    (Spanish, DReconnecting(p0)) =>
      "No se puede conectar con \{p0}; reconectando…"
    (SimplifiedChinese, DReconnecting(p0)) =>
      "无法连接 \{p0}，正在重新连接…"
    (TraditionalChinese, DReconnecting(p0)) =>
      "無法連線 \{p0}，正在重新連線…"
    (Japanese, DReconnecting(p0)) =>
      "\{p0} に接続できません。再接続中…"
    (English, DArchiveWarning(p0, p1)) =>
      "Worktree \{p0} has uncommitted changes.\{p1} Archiving deletes this checkout and permanently discards its uncommitted, untracked, and ignored files. Committed work is saved for recovery."
    (Spanish, DArchiveWarning(p0, p1)) =>
      "El worktree \{p0} tiene cambios sin confirmar.\{p1} Al archivarlo se elimina esta copia de trabajo y se descartan de forma permanente los cambios sin confirmar y los archivos sin seguimiento e ignorados. Los commits se guardan para su recuperación."
    (SimplifiedChinese, DArchiveWarning(p0, p1)) =>
      "工作树 \{p0} 中有未提交的更改。\{p1} 归档会删除此检出目录，永久丢弃未提交、未跟踪和已忽略的文件。已提交的内容将被保存以供恢复。"
    (TraditionalChinese, DArchiveWarning(p0, p1)) =>
      "工作樹 \{p0} 中有未提交的更改。\{p1} 歸檔會刪除此檢出目錄，永久丟棄未提交、未跟蹤和已忽略的檔案。已提交的內容將被儲存以供恢復。"
    (Japanese, DArchiveWarning(p0, p1)) =>
      "ワークツリー \{p0} に未コミットの変更があります。\{p1} アーカイブするとこのチェックアウトが削除され、未コミット・未追跡・無視されたファイルは完全に失われます。コミット済みの内容は復元用に保存されます。"
    (English, DArchiveQuestion(p0)) => "Archive this \{p0}?"
    (Spanish, DArchiveQuestion(_)) => "¿Archivar esta conversación?"
    (SimplifiedChinese, DArchiveQuestion(_)) => "归档此对话？"
    (TraditionalChinese, DArchiveQuestion(_)) => "歸檔此對話？"
    (Japanese, DArchiveQuestion(_)) =>
      "このチャットをアーカイブしますか？"
    (English, DWorkingStep(p0)) => "Working · step \{p0}"
    (Spanish, DWorkingStep(p0)) => "Trabajando · paso \{p0}"
    (SimplifiedChinese, DWorkingStep(p0)) => "正在处理 · 第 \{p0} 步"
    (TraditionalChinese, DWorkingStep(p0)) => "正在處理 · 第 \{p0} 步"
    (Japanese, DWorkingStep(p0)) => "処理中 · ステップ \{p0}"
    (English, DRetry(p0, p1, p2)) => "Retrying · attempt \{p0}/\{p1} · \{p2}"
    (Spanish, DRetry(p0, p1, p2)) =>
      "Reintentando · intento \{p0}/\{p1} · \{p2}"
    (SimplifiedChinese, DRetry(p0, p1, p2)) =>
      "正在重试 · 第 \{p0}/\{p1} 次 · \{p2}"
    (TraditionalChinese, DRetry(p0, p1, p2)) =>
      "正在重試 · 第 \{p0}/\{p1} 次 · \{p2}"
    (Japanese, DRetry(p0, p1, p2)) => "再試行中 · \{p0}/\{p1} 回 · \{p2}"
    (English, DFailedChecks(p0)) => "\{p0} failed"
    (Spanish, DFailedChecks(p0)) =>
      if p0 == "1" {
        "1 fallida"
      } else {
        "\{p0} fallidas"
      }
    (SimplifiedChinese, DFailedChecks(p0)) => "\{p0} 项失败"
    (TraditionalChinese, DFailedChecks(p0)) => "\{p0} 項失敗"
    (Japanese, DFailedChecks(p0)) => "\{p0} 件失敗"
    (English, DPendingChecks(p0)) => "\{p0} running"
    (Spanish, DPendingChecks(p0)) => "\{p0} en ejecución"
    (SimplifiedChinese, DPendingChecks(p0)) => "\{p0} 项运行中"
    (TraditionalChinese, DPendingChecks(p0)) => "\{p0} 項執行中"
    (Japanese, DPendingChecks(p0)) => "\{p0} 件実行中"
    (English, DPassedChecks(p0)) => "\{p0} passed"
    (Spanish, DPassedChecks(p0)) =>
      if p0 == "1" {
        "1 superada"
      } else {
        "\{p0} superadas"
      }
    (SimplifiedChinese, DPassedChecks(p0)) => "\{p0} 项通过"
    (TraditionalChinese, DPassedChecks(p0)) => "\{p0} 項透過"
    (Japanese, DPassedChecks(p0)) => "\{p0} 件成功"
    (English, DFileCount(p0)) => "\{p0} files"
    (Spanish, DFileCount(p0)) => "\{p0} archivos"
    (SimplifiedChinese, DFileCount(p0)) => "\{p0} 个文件"
    (TraditionalChinese, DFileCount(p0)) => "\{p0} 個檔案"
    (Japanese, DFileCount(p0)) => "\{p0} ファイル"
    (English, DOnBranch(p0)) => "On branch \{p0}"
    (Spanish, DOnBranch(p0)) => "En la rama \{p0}"
    (SimplifiedChinese, DOnBranch(p0)) => "当前分支 \{p0}"
    (TraditionalChinese, DOnBranch(p0)) => "當前分支 \{p0}"
    (Japanese, DOnBranch(p0)) => "現在のブランチ：\{p0}"
    (English, DFromBranch(p0)) => "from \{p0}"
    (Spanish, DFromBranch(p0)) => "de \{p0}"
    (SimplifiedChinese, DFromBranch(p0)) => "来自 \{p0}"
    (TraditionalChinese, DFromBranch(p0)) => "來自 \{p0}"
    (Japanese, DFromBranch(p0)) => "送信元：\{p0}"
    (English, DRule(p0)) => "Allow by rule: \{p0}"
    (Spanish, DRule(p0)) => "Permitir mediante regla: \{p0}"
    (SimplifiedChinese, DRule(p0)) => "按规则允许：\{p0}"
    (TraditionalChinese, DRule(p0)) => "按規則允許：\{p0}"
    (Japanese, DRule(p0)) => "ルールに従って許可：\{p0}"
  }
}
