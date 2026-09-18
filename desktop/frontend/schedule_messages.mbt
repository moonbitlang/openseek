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
    (English, TimeoutInteger) => "Enter a whole number for the timeout"
    (SimplifiedChinese, TimeoutInteger) => "请输入整数超时分钟数"
    (English, ScheduleRange) =>
      "Interval: 1–525600 minutes. Timeout: 1–1440 minutes."
    (SimplifiedChinese, ScheduleRange) =>
      "间隔：1–525600 分钟。超时：1–1440 分钟。"
    (English, ScheduleRequired) => "Enter a name and task"
    (SimplifiedChinese, ScheduleRequired) => "请输入名称和任务"
    (English, SessionUnavailable) =>
      "The session record is not available yet, or it has been archived. Check the run status and log."
    (SimplifiedChinese, SessionUnavailable) =>
      "会话记录尚不可用，或已被归档。请检查运行状态和日志。"
    (English, LogTooLarge) =>
      "This log is too large to display. Open its saved path with an external viewer."
    (SimplifiedChinese, LogTooLarge) =>
      "日志过大，无法显示。请使用外部查看器打开已保存的日志文件。"
    (English, LogNotText) => "This log is not a text file"
    (SimplifiedChinese, LogNotText) => "此日志不是文本文件"
    (English, RunningLabel) => "Running"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (English, CompletedLabel) => "Completed"
    (SimplifiedChinese, CompletedLabel) => "已完成"
    (English, FailedLabel) => "Failed · "
    (SimplifiedChinese, FailedLabel) => "失败 · "
    (English, StoppedLabel) => "Stopped"
    (SimplifiedChinese, StoppedLabel) => "已停止"
    (English, TimedOutLabel) => "Timed out"
    (SimplifiedChinese, TimedOutLabel) => "已超时"
    (English, InterruptedLabel) => "Interrupted · host stopped; not retried"
    (SimplifiedChinese, InterruptedLabel) =>
      "已中断 · 主机已停止，未重试"
    (English, ScheduledTasks) => "Scheduled tasks"
    (SimplifiedChinese, ScheduledTasks) => "定时任务"
    (English, ScheduleDescription) =>
      "Run independent OpenSeek tasks while this host is open. Missed times are skipped. Up to 4 tasks can run together; each plan runs one task at a time."
    (SimplifiedChinese, ScheduleDescription) =>
      "在此主机运行期间执行独立的 OpenSeek 任务。已错过的执行时间会跳过。最多可同时运行 4 个任务，每个计划一次运行一个任务。"
    (English, NewSchedule) => "New schedule"
    (SimplifiedChinese, NewSchedule) => "新建计划"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (English, RunLog) => "Run log"
    (SimplifiedChinese, RunLog) => "运行日志"
    (English, CloseLog) => "Close log"
    (SimplifiedChinese, CloseLog) => "关闭日志"
    (English, AutomaticallyCreate) => "Automatically create"
    (SimplifiedChinese, AutomaticallyCreate) => "自动创建"
    (English, EditSchedule) => "Edit schedule"
    (SimplifiedChinese, EditSchedule) => "编辑计划"
    (English, NameLabel) => "Name"
    (SimplifiedChinese, NameLabel) => "名称"
    (English, WorkingDirectory) => "Working directory"
    (SimplifiedChinese, WorkingDirectory) => "工作目录"
    (English, AutomaticDirectoryDescription) =>
      "OpenSeek creates a dedicated folder on the first run and reuses it to save this task's files and results."
    (SimplifiedChinese, AutomaticDirectoryDescription) =>
      "OpenSeek 会在首次运行时创建专用文件夹，并继续用它保存此任务的文件和结果。"
    (English, ProjectDirectoryDescription) =>
      "This task runs in the selected project folder and can read and update its files."
    (SimplifiedChinese, ProjectDirectoryDescription) =>
      "此任务在所选项目文件夹中运行，可读取和更新其中的文件。"
    (English, TaskLabel) => "Task"
    (SimplifiedChinese, TaskLabel) => "任务"
    (English, ScheduleLabel) => "Schedule"
    (SimplifiedChinese, ScheduleLabel) => "计划"
    (English, EveryLabel) => "Every"
    (SimplifiedChinese, EveryLabel) => "每隔"
    (English, OnceIn) => "Once, in"
    (SimplifiedChinese, OnceIn) => "延迟执行一次"
    (English, MinutesLabel) => "Minutes"
    (SimplifiedChinese, MinutesLabel) => "分钟"
    (English, TimeoutMinutes) => "Timeout (minutes)"
    (SimplifiedChinese, TimeoutMinutes) => "超时时间（分钟）"
    (English, ModelDefault) => "Model (blank uses host default)"
    (SimplifiedChinese, ModelDefault) =>
      "模型（留空使用主机默认值）"
    (English, SchedulePermissions) =>
      "Uses this host's API settings. Permission escalation is refused in unattended runs."
    (SimplifiedChinese, SchedulePermissions) =>
      "使用此主机的 API 设置。无人值守运行时不允许提升权限。"
    (English, RunNowDescription) =>
      "Save and run now executes once immediately without changing the schedule."
    (SimplifiedChinese, RunNowDescription) =>
      "“保存并立即运行”会立即执行一次，不改变计划时间。"
    (English, SaveRunNow) => "Save and run now"
    (SimplifiedChinese, SaveRunNow) => "保存并立即运行"
    (English, SaveSchedule) => "Save schedule"
    (SimplifiedChinese, SaveSchedule) => "保存计划"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (English, EmptySchedules) =>
      "No schedules yet. Create one to run a task later or at a fixed interval."
    (SimplifiedChinese, EmptySchedules) =>
      "尚无定时计划。创建计划，让任务稍后执行或定期运行。"
    (English, OnceLabel) => "Once · "
    (SimplifiedChinese, OnceLabel) => "一次 · "
    (English, NextLabel) => "Next: "
    (SimplifiedChinese, NextLabel) => "下次："
    (English, WaitingLabel) => "Waiting"
    (SimplifiedChinese, WaitingLabel) => "等待中"
    (English, PausedFinished) => "Paused / finished"
    (SimplifiedChinese, PausedFinished) => "已暂停 / 已结束"
    (English, QueuedLabel) => "Queued"
    (SimplifiedChinese, QueuedLabel) => "已排队"
    (English, AutomaticDirectory) => "Automatically created working directory"
    (SimplifiedChinese, AutomaticDirectory) => "自动创建的工作目录"
    (English, RunNow) => "Run now"
    (SimplifiedChinese, RunNow) => "立即运行"
    (English, PauseLabel) => "Pause"
    (SimplifiedChinese, PauseLabel) => "暂停"
    (English, ResumeLabel) => "Resume"
    (SimplifiedChinese, ResumeLabel) => "继续"
    (English, EditLabel) => "Edit"
    (SimplifiedChinese, EditLabel) => "编辑"
    (English, StopRun) => "Stop run"
    (SimplifiedChinese, StopRun) => "停止运行"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (English, RunHistory) => "Run history"
    (SimplifiedChinese, RunHistory) => "运行历史"
    (English, NoRunningTasks) => "No tasks are running."
    (SimplifiedChinese, NoRunningTasks) => "没有正在运行的任务。"
    (English, NoFinishedRuns) => "No finished runs yet."
    (SimplifiedChinese, NoFinishedRuns) => "尚无已结束的运行记录。"
    (English, OpenSession) => "Open session"
    (SimplifiedChinese, OpenSession) => "打开会话"
    (English, ViewLog) => "View log"
    (SimplifiedChinese, ViewLog) => "查看日志"
    (English, LogLabel) => "Log: "
    (SimplifiedChinese, LogLabel) => "日志："
  }
}
