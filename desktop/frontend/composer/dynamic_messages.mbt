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
    (SimplifiedChinese, DJump(p0)) => "跳转至 \{p0}"
    (English, DSettingGoal(p0)) => "Setting goal: \{p0}"
    (SimplifiedChinese, DSettingGoal(p0)) => "正在设置目标：\{p0}"
    (English, DGoalBlocked(p0)) => "Goal blocked: \{p0}"
    (SimplifiedChinese, DGoalBlocked(p0)) => "目标受阻：\{p0}"
    (English, DGoalBlockedDetails(p0, p1)) => "Goal: \{p0}\n\nBlocked: \{p1}"
    (SimplifiedChinese, DGoalBlockedDetails(p0, p1)) =>
      "目标：\{p0}\n\n受阻原因：\{p1}"
    (English, DGoal(p0)) => "Goal: \{p0}"
    (SimplifiedChinese, DGoal(p0)) => "目标：\{p0}"
    (English, DWorktree(p0)) => "This chat runs in worktree \{p0}"
    (SimplifiedChinese, DWorktree(p0)) =>
      "此对话在工作树 \{p0} 中运行"
    (English, DMissingWorktree(p0)) =>
      "Worktree \{p0} has no checkout. Rebuild it to continue; commits on its branch are safe."
    (SimplifiedChinese, DMissingWorktree(p0)) =>
      "工作树 \{p0} 缺少检出目录。重建后即可继续，分支上的提交仍然安全。"
    (English, DRebuildWorktree(p0)) =>
      "Check the branch out again at .worktrees/\{p0}"
    (SimplifiedChinese, DRebuildWorktree(p0)) =>
      "将分支重新检出到 .worktrees/\{p0}"
    (English, DArchiveMissing(p0)) =>
      "Archive this \{p0} without rebuilding its worktree"
    (SimplifiedChinese, DArchiveMissing(_)) =>
      "直接归档此对话，不重建工作树"
    (English, DArchiveLabel(p0)) => "Archive \{p0}"
    (SimplifiedChinese, DArchiveLabel(_)) => "归档对话"
    (English, DReconnecting(p0)) => "Can't reach \{p0} — reconnecting…"
    (SimplifiedChinese, DReconnecting(p0)) =>
      "无法连接 \{p0}，正在重新连接…"
    (English, DArchiveWarning(p0, p1)) =>
      "Worktree \{p0} has uncommitted changes.\{p1} Archiving deletes this checkout and permanently discards its uncommitted, untracked, and ignored files. Committed work and the branch remain."
    (SimplifiedChinese, DArchiveWarning(p0, p1)) =>
      "工作树 \{p0} 中有未提交的更改。\{p1} 归档会删除此检出目录，永久丢弃未提交、未跟踪和已忽略的文件。已提交的内容和分支将被保留。"
    (English, DArchiveQuestion(p0)) => "Archive this \{p0}?"
    (SimplifiedChinese, DArchiveQuestion(_)) => "归档此对话？"
    (English, DWorkingStep(p0)) => "Working · step \{p0}"
    (SimplifiedChinese, DWorkingStep(p0)) => "正在处理 · 第 \{p0} 步"
    (English, DRetry(p0, p1, p2)) => "Retrying · attempt \{p0}/\{p1} · \{p2}"
    (SimplifiedChinese, DRetry(p0, p1, p2)) =>
      "正在重试 · 第 \{p0}/\{p1} 次 · \{p2}"
    (English, DFailedChecks(p0)) => "\{p0} failed"
    (SimplifiedChinese, DFailedChecks(p0)) => "\{p0} 项失败"
    (English, DPendingChecks(p0)) => "\{p0} running"
    (SimplifiedChinese, DPendingChecks(p0)) => "\{p0} 项运行中"
    (English, DPassedChecks(p0)) => "\{p0} passed"
    (SimplifiedChinese, DPassedChecks(p0)) => "\{p0} 项通过"
    (English, DFileCount(p0)) => "\{p0} files"
    (SimplifiedChinese, DFileCount(p0)) => "\{p0} 个文件"
    (English, DOnBranch(p0)) => "On branch \{p0}"
    (SimplifiedChinese, DOnBranch(p0)) => "当前分支 \{p0}"
    (English, DFromBranch(p0)) => "from \{p0}"
    (SimplifiedChinese, DFromBranch(p0)) => "来自 \{p0}"
    (English, DRule(p0)) => "Allow by rule: \{p0}"
    (SimplifiedChinese, DRule(p0)) => "按规则允许：\{p0}"
  }
}
