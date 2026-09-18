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
    (Japanese, CleanupFailed) => "失敗 · クリーンアップ未完了"
    (English, RunningLabel) => "Running"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (Japanese, RunningLabel) => "実行中"
    (English, StoppingLabel) => "Stopping…"
    (SimplifiedChinese, StoppingLabel) => "正在停止…"
    (Japanese, StoppingLabel) => "停止中…"
    (English, CompletedLabel) => "Completed"
    (SimplifiedChinese, CompletedLabel) => "已完成"
    (Japanese, CompletedLabel) => "完了"
    (English, StoppedLabel) => "Stopped"
    (SimplifiedChinese, StoppedLabel) => "已停止"
    (Japanese, StoppedLabel) => "停止済み"
    (English, SessionEnded) => "Session ended"
    (SimplifiedChinese, SessionEnded) => "会话已结束"
    (Japanese, SessionEnded) => "セッション終了"
    (English, OutputLimit) => "Stopped · output limit reached"
    (SimplifiedChinese, OutputLimit) => "已停止 · 达到输出上限"
    (Japanese, OutputLimit) => "停止済み · 出力上限に到達"
    (English, TimeLimit) => "Stopped · time limit reached"
    (SimplifiedChinese, TimeLimit) => "已停止 · 达到时间上限"
    (Japanese, TimeLimit) => "停止済み · 時間上限に到達"
    (English, CaptureFailed) => "Stopped · output capture failed"
    (SimplifiedChinese, CaptureFailed) => "已停止 · 输出捕获失败"
    (Japanese, CaptureFailed) => "停止済み · 出力の取得に失敗"
    (English, InterruptedLabel) => "Interrupted"
    (SimplifiedChinese, InterruptedLabel) => "已中断"
    (Japanese, InterruptedLabel) => "中断済み"
    (English, EndTimeUnavailable) => "End time unavailable"
    (SimplifiedChinese, EndTimeUnavailable) => "结束时间不可用"
    (Japanese, EndTimeUnavailable) => "終了時刻は不明です"
    (English, BackgroundJobs) => "Background jobs"
    (SimplifiedChinese, BackgroundJobs) => "后台任务"
    (Japanese, BackgroundJobs) => "バックグラウンドジョブ"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (Japanese, RefreshLabel) => "更新"
    (English, DisconnectedDescription) =>
      "Disconnected. Output remains on the host; reconnect to refresh."
    (SimplifiedChinese, DisconnectedDescription) =>
      "连接已断开。输出仍保留在主机上，重新连接后可刷新。"
    (Japanese, DisconnectedDescription) =>
      "接続が切れました。出力はホストに保持されています。再接続後に更新してください。"
    (English, LoadingJobs) => "Loading jobs…"
    (SimplifiedChinese, LoadingJobs) => "正在加载后台任务…"
    (Japanese, LoadingJobs) =>
      "バックグラウンドジョブを読み込み中…"
    (English, NoJobs) => "No background jobs yet"
    (SimplifiedChinese, NoJobs) => "尚无后台任务"
    (Japanese, NoJobs) => "バックグラウンドジョブはありません"
    (English, JobsDescription) =>
      "Commands appear here when they move to the background. Their output files stay with this conversation."
    (SimplifiedChinese, JobsDescription) =>
      "转入后台的命令会显示在此处。输出文件随此对话保留。"
    (Japanese, JobsDescription) =>
      "バックグラウンドに移行したコマンドがここに表示されます。出力ファイルはこのチャットとともに保持されます。"
    (English, HistoryLabel) => "History"
    (SimplifiedChinese, HistoryLabel) => "历史记录"
    (Japanese, HistoryLabel) => "履歴"
    (English, InProgress) => "In progress"
    (SimplifiedChinese, InProgress) => "进行中"
    (Japanese, InProgress) => "進行中"
    (English, LoadOlder) => "Load older jobs"
    (SimplifiedChinese, LoadOlder) => "加载更早的任务"
    (Japanese, LoadOlder) => "以前のジョブを読み込む"
    (English, NoOutputLabel) => "No output yet"
    (SimplifiedChinese, NoOutputLabel) => "尚无输出"
    (Japanese, NoOutputLabel) => "出力はまだありません"
    (English, CopyId) => "Copy job ID"
    (SimplifiedChinese, CopyId) => "复制任务 ID"
    (Japanese, CopyId) => "ジョブ ID をコピー"
    (English, CopyPath) => "Copy path"
    (SimplifiedChinese, CopyPath) => "复制路径"
    (Japanese, CopyPath) => "パスをコピー"
    (English, CopyTail) => "Copy tail command"
    (SimplifiedChinese, CopyTail) => "复制日志跟踪命令"
    (Japanese, CopyTail) => "ログ追跡コマンドをコピー"
    (English, ReloadTail) => "Reload tail"
    (SimplifiedChinese, ReloadTail) => "重新加载日志末尾"
    (Japanese, ReloadTail) => "ログの末尾を再読み込み"
    (English, PauseLabel) => "Pause"
    (SimplifiedChinese, PauseLabel) => "暂停"
    (Japanese, PauseLabel) => "一時停止"
    (English, FollowOutput) => "Follow output"
    (SimplifiedChinese, FollowOutput) => "跟踪输出"
    (Japanese, FollowOutput) => "出力を追跡"
    (English, StopJob) => "Stop job"
    (SimplifiedChinese, StopJob) => "停止任务"
    (Japanese, StopJob) => "ジョブを停止"
    (English, TruncatedOutput) =>
      "Output capture reached its limit; the retained log is truncated."
    (SimplifiedChinese, TruncatedOutput) =>
      "输出捕获已达上限，保留的日志已截断。"
    (Japanese, TruncatedOutput) =>
      "出力の取得上限に達しました。保存されたログは切り詰められています。"
    (English, InvalidUtf8) =>
      "Output contained invalid UTF-8; replacement characters were saved."
    (SimplifiedChinese, InvalidUtf8) =>
      "输出包含无效的 UTF-8，已保存为替代字符。"
    (Japanese, InvalidUtf8) =>
      "出力に無効な UTF-8 が含まれていたため、置換文字で保存されました。"
    (English, NoLogFile) => "No retained log file for this job."
    (SimplifiedChinese, NoLogFile) => "此任务没有保留的日志文件。"
    (Japanese, NoLogFile) =>
      "このジョブには保存されたログファイルがありません。"
    (English, OutputUnavailable) => "Output unavailable · reload to retry."
    (SimplifiedChinese, OutputUnavailable) =>
      "输出不可用 · 重新加载以重试。"
    (Japanese, OutputUnavailable) =>
      "出力を取得できません。再読み込みして再試行してください。"
    (English, OutputEnded) => "Output ended"
    (SimplifiedChinese, OutputEnded) => "输出已结束"
    (Japanese, OutputEnded) => "出力が終了しました"
    (English, LoadingRemaining) => "Loading remaining output…"
    (SimplifiedChinese, LoadingRemaining) => "正在加载剩余输出…"
    (Japanese, LoadingRemaining) => "残りの出力を読み込み中…"
    (English, CatchingUp) => "Catching up with output…"
    (SimplifiedChinese, CatchingUp) => "正在同步输出…"
    (Japanese, CatchingUp) => "出力を同期中…"
    (English, FollowingOutput) => "Following output"
    (SimplifiedChinese, FollowingOutput) => "正在跟踪输出"
    (Japanese, FollowingOutput) => "出力を追跡中"
    (English, PausedOutput) => "Paused · output continues to the file"
    (SimplifiedChinese, PausedOutput) => "已暂停 · 输出继续写入文件"
    (Japanese, PausedOutput) =>
      "一時停止中 · ファイルへの出力は継続しています"
    (English, JobOutput) => "Job output"
    (SimplifiedChinese, JobOutput) => "任务输出"
    (Japanese, JobOutput) => "ジョブの出力"
    (English, LoadingOutput) => "Loading output…"
    (SimplifiedChinese, LoadingOutput) => "正在加载输出…"
    (Japanese, LoadingOutput) => "出力を読み込み中…"
    (English, NoRetainedOutput) => "No retained output."
    (SimplifiedChinese, NoRetainedOutput) => "没有保留的输出。"
    (Japanese, NoRetainedOutput) => "保存された出力はありません。"
    (English, NoOutputYet) => "No output yet."
    (SimplifiedChinese, NoOutputYet) => "尚无输出。"
    (Japanese, NoOutputYet) => "出力はまだありません。"
    (English, StopDescription) =>
      "Stop controls the direct process. Logs are retained with the session."
    (SimplifiedChinese, StopDescription) =>
      "停止操作作用于直接进程。日志随会话保留。"
    (Japanese, StopDescription) =>
      "停止操作は直接のプロセスに適用されます。ログはセッションとともに保持されます。"
  }
}
