// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  CleanupFailed
  RunningLabel
  StoppingLabel
  CompletedLabel
  StoppedLabel
  SessionEnded
  OutputLimit
  TimeLimit
  CaptureFailed
  InterruptedLabel
  EndTimeUnavailable
  BackgroundJobs
  RefreshLabel
  DisconnectedDescription
  LoadingJobs
  NoJobs
  JobsDescription
  HistoryLabel
  InProgress
  LoadOlder
  NoOutputLabel
  CopyId
  CopyPath
  CopyTail
  ReloadTail
  PauseLabel
  FollowOutput
  StopJob
  TruncatedOutput
  InvalidUtf8
  NoLogFile
  OutputUnavailable
  OutputEnded
  LoadingRemaining
  CatchingUp
  FollowingOutput
  PausedOutput
  JobOutput
  LoadingOutput
  NoRetainedOutput
  NoOutputYet
  StopDescription
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, CleanupFailed) => "Failed · cleanup incomplete"
    (SimplifiedChinese, CleanupFailed) => "失败 · 清理未完成"
    (English, RunningLabel) => "Running"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (English, StoppingLabel) => "Stopping…"
    (SimplifiedChinese, StoppingLabel) => "正在停止…"
    (English, CompletedLabel) => "Completed"
    (SimplifiedChinese, CompletedLabel) => "已完成"
    (English, StoppedLabel) => "Stopped"
    (SimplifiedChinese, StoppedLabel) => "已停止"
    (English, SessionEnded) => "Session ended"
    (SimplifiedChinese, SessionEnded) => "会话已结束"
    (English, OutputLimit) => "Stopped · output limit reached"
    (SimplifiedChinese, OutputLimit) => "已停止 · 达到输出上限"
    (English, TimeLimit) => "Stopped · time limit reached"
    (SimplifiedChinese, TimeLimit) => "已停止 · 达到时间上限"
    (English, CaptureFailed) => "Stopped · output capture failed"
    (SimplifiedChinese, CaptureFailed) => "已停止 · 输出捕获失败"
    (English, InterruptedLabel) => "Interrupted"
    (SimplifiedChinese, InterruptedLabel) => "已中断"
    (English, EndTimeUnavailable) => "End time unavailable"
    (SimplifiedChinese, EndTimeUnavailable) => "结束时间不可用"
    (English, BackgroundJobs) => "Background jobs"
    (SimplifiedChinese, BackgroundJobs) => "后台任务"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (English, DisconnectedDescription) =>
      "Disconnected. Output remains on the host; reconnect to refresh."
    (SimplifiedChinese, DisconnectedDescription) =>
      "连接已断开。输出仍保留在主机上，重新连接后可刷新。"
    (English, LoadingJobs) => "Loading jobs…"
    (SimplifiedChinese, LoadingJobs) => "正在加载后台任务…"
    (English, NoJobs) => "No background jobs yet"
    (SimplifiedChinese, NoJobs) => "尚无后台任务"
    (English, JobsDescription) =>
      "Commands appear here when they move to the background. Their output files stay with this conversation."
    (SimplifiedChinese, JobsDescription) =>
      "转入后台的命令会显示在此处。输出文件随此对话保留。"
    (English, HistoryLabel) => "History"
    (SimplifiedChinese, HistoryLabel) => "历史记录"
    (English, InProgress) => "In progress"
    (SimplifiedChinese, InProgress) => "进行中"
    (English, LoadOlder) => "Load older jobs"
    (SimplifiedChinese, LoadOlder) => "加载更早的任务"
    (English, NoOutputLabel) => "No output yet"
    (SimplifiedChinese, NoOutputLabel) => "尚无输出"
    (English, CopyId) => "Copy job ID"
    (SimplifiedChinese, CopyId) => "复制任务 ID"
    (English, CopyPath) => "Copy path"
    (SimplifiedChinese, CopyPath) => "复制路径"
    (English, CopyTail) => "Copy tail command"
    (SimplifiedChinese, CopyTail) => "复制日志跟踪命令"
    (English, ReloadTail) => "Reload tail"
    (SimplifiedChinese, ReloadTail) => "重新加载日志末尾"
    (English, PauseLabel) => "Pause"
    (SimplifiedChinese, PauseLabel) => "暂停"
    (English, FollowOutput) => "Follow output"
    (SimplifiedChinese, FollowOutput) => "跟踪输出"
    (English, StopJob) => "Stop job"
    (SimplifiedChinese, StopJob) => "停止任务"
    (English, TruncatedOutput) =>
      "Output capture reached its limit; the retained log is truncated."
    (SimplifiedChinese, TruncatedOutput) =>
      "输出捕获已达上限，保留的日志已截断。"
    (English, InvalidUtf8) =>
      "Output contained invalid UTF-8; replacement characters were saved."
    (SimplifiedChinese, InvalidUtf8) =>
      "输出包含无效的 UTF-8，已保存为替代字符。"
    (English, NoLogFile) => "No retained log file for this job."
    (SimplifiedChinese, NoLogFile) => "此任务没有保留的日志文件。"
    (English, OutputUnavailable) => "Output unavailable · reload to retry."
    (SimplifiedChinese, OutputUnavailable) =>
      "输出不可用 · 重新加载以重试。"
    (English, OutputEnded) => "Output ended"
    (SimplifiedChinese, OutputEnded) => "输出已结束"
    (English, LoadingRemaining) => "Loading remaining output…"
    (SimplifiedChinese, LoadingRemaining) => "正在加载剩余输出…"
    (English, CatchingUp) => "Catching up with output…"
    (SimplifiedChinese, CatchingUp) => "正在同步输出…"
    (English, FollowingOutput) => "Following output"
    (SimplifiedChinese, FollowingOutput) => "正在跟踪输出"
    (English, PausedOutput) => "Paused · output continues to the file"
    (SimplifiedChinese, PausedOutput) => "已暂停 · 输出继续写入文件"
    (English, JobOutput) => "Job output"
    (SimplifiedChinese, JobOutput) => "任务输出"
    (English, LoadingOutput) => "Loading output…"
    (SimplifiedChinese, LoadingOutput) => "正在加载输出…"
    (English, NoRetainedOutput) => "No retained output."
    (SimplifiedChinese, NoRetainedOutput) => "没有保留的输出。"
    (English, NoOutputYet) => "No output yet."
    (SimplifiedChinese, NoOutputYet) => "尚无输出。"
    (English, StopDescription) =>
      "Stop controls the direct process. Logs are retained with the session."
    (SimplifiedChinese, StopDescription) =>
      "停止操作作用于直接进程。日志随会话保留。"
  }
}
