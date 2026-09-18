// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  MinutesInteger
  TimeoutInteger
  ScheduleRange
  ScheduleRequired
  SessionUnavailable
  LogTooLarge
  LogNotText
  RunningLabel
  CompletedLabel
  FailedLabel
  StoppedLabel
  TimedOutLabel
  InterruptedLabel
  ScheduledTasks
  ScheduleDescription
  NewSchedule
  RefreshLabel
  RunLog
  CloseLog
  AutomaticallyCreate
  EditSchedule
  NameLabel
  WorkingDirectory
  AutomaticDirectoryDescription
  ProjectDirectoryDescription
  TaskLabel
  ScheduleLabel
  EveryLabel
  OnceIn
  MinutesLabel
  TimeoutMinutes
  ModelDefault
  SchedulePermissions
  RunNowDescription
  SaveRunNow
  SaveSchedule
  CancelLabel
  EmptySchedules
  OnceLabel
  NextLabel
  WaitingLabel
  PausedFinished
  QueuedLabel
  AutomaticDirectory
  RunNow
  PauseLabel
  ResumeLabel
  EditLabel
  StopRun
  DeleteLabel
  RunHistory
  NoRunningTasks
  NoFinishedRuns
  OpenSession
  ViewLog
  LogLabel
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, MinutesInteger) => "Enter a whole number of minutes"
    (SimplifiedChinese, MinutesInteger) => "请输入整数分钟数"
    (TraditionalChinese, MinutesInteger) => "請輸入整數分鐘數"
    (Japanese, MinutesInteger) => "分数を整数で入力してください"
    (English, TimeoutInteger) => "Enter a whole number for the timeout"
    (SimplifiedChinese, TimeoutInteger) => "请输入整数超时分钟数"
    (TraditionalChinese, TimeoutInteger) => "請輸入整數逾時分鐘數"
    (Japanese, TimeoutInteger) =>
      "タイムアウトの分数を整数で入力してください"
    (English, ScheduleRange) =>
      "Interval: 1–525600 minutes. Timeout: 1–1440 minutes."
    (SimplifiedChinese, ScheduleRange) =>
      "间隔：1–525600 分钟。超时：1–1440 分钟。"
    (TraditionalChinese, ScheduleRange) =>
      "間隔：1–525600 分鐘。逾時：1–1440 分鐘。"
    (Japanese, ScheduleRange) =>
      "間隔：1〜525600 分。タイムアウト：1〜1440 分。"
    (English, ScheduleRequired) => "Enter a name and task"
    (SimplifiedChinese, ScheduleRequired) => "请输入名称和任务"
    (TraditionalChinese, ScheduleRequired) => "請輸入名稱和任務"
    (Japanese, ScheduleRequired) =>
      "名前とタスクを入力してください"
    (English, SessionUnavailable) =>
      "The session record is not available yet, or it has been archived. Check the run status and log."
    (SimplifiedChinese, SessionUnavailable) =>
      "会话记录尚不可用，或已被归档。请检查运行状态和日志。"
    (TraditionalChinese, SessionUnavailable) =>
      "會話記錄尚不可用，或已被歸檔。請檢查執行狀態和日誌。"
    (Japanese, SessionUnavailable) =>
      "セッションの記録はまだ利用できないか、アーカイブ済みです。実行状態とログを確認してください。"
    (English, LogTooLarge) =>
      "This log is too large to display. Open its saved path with an external viewer."
    (SimplifiedChinese, LogTooLarge) =>
      "日志过大，无法显示。请使用外部查看器打开已保存的日志文件。"
    (TraditionalChinese, LogTooLarge) =>
      "日誌過大，無法顯示。請使用外部檢視器開啟已儲存的日誌檔案。"
    (Japanese, LogTooLarge) =>
      "ログが大きすぎて表示できません。保存されたログファイルを外部ビューアーで開いてください。"
    (English, LogNotText) => "This log is not a text file"
    (SimplifiedChinese, LogNotText) => "此日志不是文本文件"
    (TraditionalChinese, LogNotText) => "此日誌不是文字檔案"
    (Japanese, LogNotText) =>
      "このログはテキストファイルではありません"
    (English, RunningLabel) => "Running"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (TraditionalChinese, RunningLabel) => "執行中"
    (Japanese, RunningLabel) => "実行中"
    (English, CompletedLabel) => "Completed"
    (SimplifiedChinese, CompletedLabel) => "已完成"
    (TraditionalChinese, CompletedLabel) => "已完成"
    (Japanese, CompletedLabel) => "完了"
    (English, FailedLabel) => "Failed · "
    (SimplifiedChinese, FailedLabel) => "失败 · "
    (TraditionalChinese, FailedLabel) => "失敗 · "
    (Japanese, FailedLabel) => "失敗 · "
    (English, StoppedLabel) => "Stopped"
    (SimplifiedChinese, StoppedLabel) => "已停止"
    (TraditionalChinese, StoppedLabel) => "已停止"
    (Japanese, StoppedLabel) => "停止済み"
    (English, TimedOutLabel) => "Timed out"
    (SimplifiedChinese, TimedOutLabel) => "已超时"
    (TraditionalChinese, TimedOutLabel) => "已逾時"
    (Japanese, TimedOutLabel) => "タイムアウト"
    (English, InterruptedLabel) => "Interrupted · host stopped; not retried"
    (SimplifiedChinese, InterruptedLabel) =>
      "已中断 · 主机已停止，未重试"
    (TraditionalChinese, InterruptedLabel) =>
      "已中斷 · 主機已停止，未重試"
    (Japanese, InterruptedLabel) =>
      "中断済み · ホストが停止したため再試行していません"
    (English, ScheduledTasks) => "Scheduled tasks"
    (SimplifiedChinese, ScheduledTasks) => "定时任务"
    (TraditionalChinese, ScheduledTasks) => "定時任務"
    (Japanese, ScheduledTasks) => "スケジュールタスク"
    (English, ScheduleDescription) =>
      "Run independent OpenSeek tasks while this host is open. Missed times are skipped. Up to 4 tasks can run together; each plan runs one task at a time."
    (SimplifiedChinese, ScheduleDescription) =>
      "在此主机运行期间执行独立的 OpenSeek 任务。已错过的执行时间会跳过。最多可同时运行 4 个任务，每个计划一次运行一个任务。"
    (TraditionalChinese, ScheduleDescription) =>
      "在此主機執行期間執行獨立的 OpenSeek 任務。已錯過的執行時間會跳過。最多可同時執行 4 個任務，每個計劃一次執行一個任務。"
    (Japanese, ScheduleDescription) =>
      "このホストの起動中に独立した OpenSeek タスクを実行します。過ぎた実行時刻はスキップします。同時に最大 4 タスク、各スケジュールにつき 1 タスクを実行できます。"
    (English, NewSchedule) => "New schedule"
    (SimplifiedChinese, NewSchedule) => "新建计划"
    (TraditionalChinese, NewSchedule) => "新建計劃"
    (Japanese, NewSchedule) => "新しいスケジュール"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (TraditionalChinese, RefreshLabel) => "重新整理"
    (Japanese, RefreshLabel) => "更新"
    (English, RunLog) => "Run log"
    (SimplifiedChinese, RunLog) => "运行日志"
    (TraditionalChinese, RunLog) => "執行日誌"
    (Japanese, RunLog) => "実行ログ"
    (English, CloseLog) => "Close log"
    (SimplifiedChinese, CloseLog) => "关闭日志"
    (TraditionalChinese, CloseLog) => "關閉日誌"
    (Japanese, CloseLog) => "ログを閉じる"
    (English, AutomaticallyCreate) => "Automatically create"
    (SimplifiedChinese, AutomaticallyCreate) => "自动创建"
    (TraditionalChinese, AutomaticallyCreate) => "自動建立"
    (Japanese, AutomaticallyCreate) => "自動作成"
    (English, EditSchedule) => "Edit schedule"
    (SimplifiedChinese, EditSchedule) => "编辑计划"
    (TraditionalChinese, EditSchedule) => "編輯計劃"
    (Japanese, EditSchedule) => "スケジュールを編集"
    (English, NameLabel) => "Name"
    (SimplifiedChinese, NameLabel) => "名称"
    (TraditionalChinese, NameLabel) => "名稱"
    (Japanese, NameLabel) => "名前"
    (English, WorkingDirectory) => "Working directory"
    (SimplifiedChinese, WorkingDirectory) => "工作目录"
    (TraditionalChinese, WorkingDirectory) => "工作目錄"
    (Japanese, WorkingDirectory) => "作業ディレクトリ"
    (English, AutomaticDirectoryDescription) =>
      "OpenSeek creates a dedicated folder on the first run and reuses it to save this task's files and results."
    (SimplifiedChinese, AutomaticDirectoryDescription) =>
      "OpenSeek 会在首次运行时创建专用文件夹，并继续用它保存此任务的文件和结果。"
    (TraditionalChinese, AutomaticDirectoryDescription) =>
      "OpenSeek 會在首次執行時建立專用資料夾，並繼續用它儲存此任務的檔案和結果。"
    (Japanese, AutomaticDirectoryDescription) =>
      "OpenSeek は初回実行時に専用フォルダーを作成し、以降もタスクのファイルと結果の保存に使用します。"
    (English, ProjectDirectoryDescription) =>
      "This task runs in the selected project folder and can read and update its files."
    (SimplifiedChinese, ProjectDirectoryDescription) =>
      "此任务在所选项目文件夹中运行，可读取和更新其中的文件。"
    (TraditionalChinese, ProjectDirectoryDescription) =>
      "此任務在所選專案資料夾中執行，可讀取和更新其中的檔案。"
    (Japanese, ProjectDirectoryDescription) =>
      "このタスクは選択したプロジェクトフォルダーで実行され、その中のファイルを読み取り・更新できます。"
    (English, TaskLabel) => "Task"
    (SimplifiedChinese, TaskLabel) => "任务"
    (TraditionalChinese, TaskLabel) => "任務"
    (Japanese, TaskLabel) => "タスク"
    (English, ScheduleLabel) => "Schedule"
    (SimplifiedChinese, ScheduleLabel) => "计划"
    (TraditionalChinese, ScheduleLabel) => "計劃"
    (Japanese, ScheduleLabel) => "スケジュール"
    (English, EveryLabel) => "Every"
    (SimplifiedChinese, EveryLabel) => "每隔"
    (TraditionalChinese, EveryLabel) => "每隔"
    (Japanese, EveryLabel) => "定期実行"
    (English, OnceIn) => "Once, in"
    (SimplifiedChinese, OnceIn) => "延迟执行一次"
    (TraditionalChinese, OnceIn) => "延遲執行一次"
    (Japanese, OnceIn) => "指定時間後に一度実行"
    (English, MinutesLabel) => "Minutes"
    (SimplifiedChinese, MinutesLabel) => "分钟"
    (TraditionalChinese, MinutesLabel) => "分鐘"
    (Japanese, MinutesLabel) => "分"
    (English, TimeoutMinutes) => "Timeout (minutes)"
    (SimplifiedChinese, TimeoutMinutes) => "超时时间（分钟）"
    (TraditionalChinese, TimeoutMinutes) => "逾時時間（分鐘）"
    (Japanese, TimeoutMinutes) => "タイムアウト（分）"
    (English, ModelDefault) => "Model (blank uses host default)"
    (SimplifiedChinese, ModelDefault) =>
      "模型（留空使用主机默认值）"
    (TraditionalChinese, ModelDefault) =>
      "模型（留空使用主機預設值）"
    (Japanese, ModelDefault) =>
      "モデル（空欄でホストの既定値を使用）"
    (English, SchedulePermissions) =>
      "Uses this host's API settings. Permission escalation is refused in unattended runs."
    (SimplifiedChinese, SchedulePermissions) =>
      "使用此主机的 API 设置。无人值守运行时不允许提升权限。"
    (TraditionalChinese, SchedulePermissions) =>
      "使用此主機的 API 設定。無人值守執行時不允許提升許可權。"
    (Japanese, SchedulePermissions) =>
      "このホストの API 設定を使用します。無人実行時の権限昇格は許可されません。"
    (English, RunNowDescription) =>
      "Save and run now executes once immediately without changing the schedule."
    (SimplifiedChinese, RunNowDescription) =>
      "“保存并立即运行”会立即执行一次，不改变计划时间。"
    (TraditionalChinese, RunNowDescription) =>
      "“儲存並立即執行”會立即執行一次，不改變計劃時間。"
    (Japanese, RunNowDescription) =>
      "「保存して今すぐ実行」はスケジュール時刻を変更せず、一度実行します。"
    (English, SaveRunNow) => "Save and run now"
    (SimplifiedChinese, SaveRunNow) => "保存并立即运行"
    (TraditionalChinese, SaveRunNow) => "儲存並立即執行"
    (Japanese, SaveRunNow) => "保存して今すぐ実行"
    (English, SaveSchedule) => "Save schedule"
    (SimplifiedChinese, SaveSchedule) => "保存计划"
    (TraditionalChinese, SaveSchedule) => "儲存計劃"
    (Japanese, SaveSchedule) => "スケジュールを保存"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, EmptySchedules) =>
      "No schedules yet. Create one to run a task later or at a fixed interval."
    (SimplifiedChinese, EmptySchedules) =>
      "尚无定时计划。创建计划，让任务稍后执行或定期运行。"
    (TraditionalChinese, EmptySchedules) =>
      "尚無定時計劃。建立計劃，讓任務稍後執行或定期執行。"
    (Japanese, EmptySchedules) =>
      "スケジュールがありません。タスクを後で、または定期的に実行するスケジュールを作成してください。"
    (English, OnceLabel) => "Once · "
    (SimplifiedChinese, OnceLabel) => "一次 · "
    (TraditionalChinese, OnceLabel) => "一次 · "
    (Japanese, OnceLabel) => "一度 · "
    (English, NextLabel) => "Next: "
    (SimplifiedChinese, NextLabel) => "下次："
    (TraditionalChinese, NextLabel) => "下次："
    (Japanese, NextLabel) => "次回："
    (English, WaitingLabel) => "Waiting"
    (SimplifiedChinese, WaitingLabel) => "等待中"
    (TraditionalChinese, WaitingLabel) => "等待中"
    (Japanese, WaitingLabel) => "待機中"
    (English, PausedFinished) => "Paused / finished"
    (SimplifiedChinese, PausedFinished) => "已暂停 / 已结束"
    (TraditionalChinese, PausedFinished) => "已暫停 / 已結束"
    (Japanese, PausedFinished) => "一時停止 / 終了"
    (English, QueuedLabel) => "Queued"
    (SimplifiedChinese, QueuedLabel) => "已排队"
    (TraditionalChinese, QueuedLabel) => "已排隊"
    (Japanese, QueuedLabel) => "待機中"
    (English, AutomaticDirectory) => "Automatically created working directory"
    (SimplifiedChinese, AutomaticDirectory) => "自动创建的工作目录"
    (TraditionalChinese, AutomaticDirectory) => "自動建立的工作目錄"
    (Japanese, AutomaticDirectory) =>
      "自動作成された作業ディレクトリ"
    (English, RunNow) => "Run now"
    (SimplifiedChinese, RunNow) => "立即运行"
    (TraditionalChinese, RunNow) => "立即執行"
    (Japanese, RunNow) => "今すぐ実行"
    (English, PauseLabel) => "Pause"
    (SimplifiedChinese, PauseLabel) => "暂停"
    (TraditionalChinese, PauseLabel) => "暫停"
    (Japanese, PauseLabel) => "一時停止"
    (English, ResumeLabel) => "Resume"
    (SimplifiedChinese, ResumeLabel) => "继续"
    (TraditionalChinese, ResumeLabel) => "繼續"
    (Japanese, ResumeLabel) => "再開"
    (English, EditLabel) => "Edit"
    (SimplifiedChinese, EditLabel) => "编辑"
    (TraditionalChinese, EditLabel) => "編輯"
    (Japanese, EditLabel) => "編集"
    (English, StopRun) => "Stop run"
    (SimplifiedChinese, StopRun) => "停止运行"
    (TraditionalChinese, StopRun) => "停止執行"
    (Japanese, StopRun) => "実行を停止"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (TraditionalChinese, DeleteLabel) => "刪除"
    (Japanese, DeleteLabel) => "削除"
    (English, RunHistory) => "Run history"
    (SimplifiedChinese, RunHistory) => "运行历史"
    (TraditionalChinese, RunHistory) => "執行歷史"
    (Japanese, RunHistory) => "実行履歴"
    (English, NoRunningTasks) => "No tasks are running."
    (SimplifiedChinese, NoRunningTasks) => "没有正在运行的任务。"
    (TraditionalChinese, NoRunningTasks) => "沒有正在執行的任務。"
    (Japanese, NoRunningTasks) => "実行中のタスクはありません。"
    (English, NoFinishedRuns) => "No finished runs yet."
    (SimplifiedChinese, NoFinishedRuns) => "尚无已结束的运行记录。"
    (TraditionalChinese, NoFinishedRuns) => "尚無已結束的執行記錄。"
    (Japanese, NoFinishedRuns) =>
      "終了した実行履歴はまだありません。"
    (English, OpenSession) => "Open session"
    (SimplifiedChinese, OpenSession) => "打开会话"
    (TraditionalChinese, OpenSession) => "開啟會話"
    (Japanese, OpenSession) => "セッションを開く"
    (English, ViewLog) => "View log"
    (SimplifiedChinese, ViewLog) => "查看日志"
    (TraditionalChinese, ViewLog) => "檢視日誌"
    (Japanese, ViewLog) => "ログを表示"
    (English, LogLabel) => "Log: "
    (SimplifiedChinese, LogLabel) => "日志："
    (TraditionalChinese, LogLabel) => "日誌："
    (Japanese, LogLabel) => "ログ："
  }
}
