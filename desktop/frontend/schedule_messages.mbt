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
  PausedStatus
  FinishedStatus
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
  RecordedFailure
  LogUnreadable
  SkippedPreviousRunActive
  SkippedCapacityFull
  SkippedMissedTime
  SkippedAutomaticFolderUnavailable
  RefusedForeignOwner
  RefusedMissing
  RefusedUnattachedProject
  RefusedPastTime
  RefusedAlreadyRunning
  RefusedAlreadyQueued
  RefusedStopBeforeDelete
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, MinutesInteger) => "Enter a whole number of minutes"
    (Spanish, MinutesInteger) => "Introduce un número entero de minutos"
    (SimplifiedChinese, MinutesInteger) => "请输入整数分钟数"
    (TraditionalChinese, MinutesInteger) => "請輸入整數分鐘數"
    (Japanese, MinutesInteger) => "分数を整数で入力してください"
    (English, TimeoutInteger) => "Enter a whole number for the timeout"
    (Spanish, TimeoutInteger) =>
      "Introduce un número entero para el tiempo de espera"
    (SimplifiedChinese, TimeoutInteger) => "请输入整数超时分钟数"
    (TraditionalChinese, TimeoutInteger) => "請輸入整數逾時分鐘數"
    (Japanese, TimeoutInteger) =>
      "タイムアウトの分数を整数で入力してください"
    (English, ScheduleRange) =>
      "Interval: 1–525600 minutes. Timeout: 1–1440 minutes."
    (Spanish, ScheduleRange) =>
      "Intervalo: 1–525600 minutos. Tiempo de espera: 1–1440 minutos."
    (SimplifiedChinese, ScheduleRange) =>
      "间隔：1–525600 分钟。超时：1–1440 分钟。"
    (TraditionalChinese, ScheduleRange) =>
      "間隔：1–525600 分鐘。逾時：1–1440 分鐘。"
    (Japanese, ScheduleRange) =>
      "間隔：1〜525600 分。タイムアウト：1〜1440 分。"
    (English, ScheduleRequired) => "Enter a name and task"
    (Spanish, ScheduleRequired) => "Introduce un nombre y una tarea"
    (SimplifiedChinese, ScheduleRequired) => "请输入名称和任务"
    (TraditionalChinese, ScheduleRequired) => "請輸入名稱和任務"
    (Japanese, ScheduleRequired) =>
      "名前とタスクを入力してください"
    (English, SessionUnavailable) =>
      "The session record is not available yet, or it has been archived. Check the run status and log."
    (Spanish, SessionUnavailable) =>
      "El registro de la sesión aún no está disponible o se ha archivado. Consulta el estado de la ejecución y el registro."
    (SimplifiedChinese, SessionUnavailable) =>
      "会话记录尚不可用，或已被归档。请检查运行状态和日志。"
    (TraditionalChinese, SessionUnavailable) =>
      "會話記錄尚不可用，或已被歸檔。請檢查執行狀態和日誌。"
    (Japanese, SessionUnavailable) =>
      "セッションの記録はまだ利用できないか、アーカイブ済みです。実行状態とログを確認してください。"
    (English, LogTooLarge) =>
      "This log is too large to display. Open its saved path with an external viewer."
    (Spanish, LogTooLarge) =>
      "Este registro es demasiado grande para mostrarlo. Abre la ruta guardada con un visor externo."
    (SimplifiedChinese, LogTooLarge) =>
      "日志过大，无法显示。请使用外部查看器打开已保存的日志文件。"
    (TraditionalChinese, LogTooLarge) =>
      "日誌過大，無法顯示。請使用外部檢視器開啟已儲存的日誌檔案。"
    (Japanese, LogTooLarge) =>
      "ログが大きすぎて表示できません。保存されたログファイルを外部ビューアーで開いてください。"
    (English, LogNotText) => "This log is not a text file"
    (Spanish, LogNotText) => "Este registro no es un archivo de texto"
    (SimplifiedChinese, LogNotText) => "此日志不是文本文件"
    (TraditionalChinese, LogNotText) => "此日誌不是文字檔案"
    (Japanese, LogNotText) =>
      "このログはテキストファイルではありません"
    (English, RunningLabel) => "Running"
    (Spanish, RunningLabel) => "En ejecución"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (TraditionalChinese, RunningLabel) => "執行中"
    (Japanese, RunningLabel) => "実行中"
    (English, CompletedLabel) => "Completed"
    (Spanish, CompletedLabel) => "Completado"
    (SimplifiedChinese, CompletedLabel) => "已完成"
    (TraditionalChinese, CompletedLabel) => "已完成"
    (Japanese, CompletedLabel) => "完了"
    (English, FailedLabel) => "Failed · "
    (Spanish, FailedLabel) => "Falló · "
    (SimplifiedChinese, FailedLabel) => "失败 · "
    (TraditionalChinese, FailedLabel) => "失敗 · "
    (Japanese, FailedLabel) => "失敗 · "
    (English, StoppedLabel) => "Stopped"
    (Spanish, StoppedLabel) => "Detenido"
    (SimplifiedChinese, StoppedLabel) => "已停止"
    (TraditionalChinese, StoppedLabel) => "已停止"
    (Japanese, StoppedLabel) => "停止済み"
    (English, TimedOutLabel) => "Timed out"
    (Spanish, TimedOutLabel) => "Tiempo de espera agotado"
    (SimplifiedChinese, TimedOutLabel) => "已超时"
    (TraditionalChinese, TimedOutLabel) => "已逾時"
    (Japanese, TimedOutLabel) => "タイムアウト"
    (English, InterruptedLabel) => "Interrupted · host stopped; not retried"
    (Spanish, InterruptedLabel) =>
      "Interrumpido · host detenido; no se reintentó"
    (SimplifiedChinese, InterruptedLabel) =>
      "已中断 · 主机已停止，未重试"
    (TraditionalChinese, InterruptedLabel) =>
      "已中斷 · 主機已停止，未重試"
    (Japanese, InterruptedLabel) =>
      "中断済み · ホストが停止したため再試行していません"
    (English, ScheduledTasks) => "Scheduled tasks"
    (Spanish, ScheduledTasks) => "Tareas programadas"
    (SimplifiedChinese, ScheduledTasks) => "定时任务"
    (TraditionalChinese, ScheduledTasks) => "定時任務"
    (Japanese, ScheduledTasks) => "スケジュールタスク"
    (English, ScheduleDescription) =>
      "Run tasks automatically while this host is running. A time that passes while the host is off or asleep is skipped."
    (Spanish, ScheduleDescription) =>
      "Ejecuta tareas automáticamente mientras este host está en marcha. Se omite una hora que pasa mientras el host está apagado o en reposo."
    (SimplifiedChinese, ScheduleDescription) =>
      "在此主机运行期间自动执行任务。主机关闭或休眠期间错过的时间会被跳过。"
    (TraditionalChinese, ScheduleDescription) =>
      "在此主機執行期間自動執行任務。主機關閉或休眠期間錯過的時間會被略過。"
    (Japanese, ScheduleDescription) =>
      "このホストの実行中にタスクを自動で実行します。ホストの停止中やスリープ中に過ぎた時刻はスキップされます。"
    (English, NewSchedule) => "New schedule"
    (Spanish, NewSchedule) => "Nueva programación"
    (SimplifiedChinese, NewSchedule) => "新建计划"
    (TraditionalChinese, NewSchedule) => "新建計劃"
    (Japanese, NewSchedule) => "新しいスケジュール"
    (English, RefreshLabel) => "Refresh"
    (Spanish, RefreshLabel) => "Actualizar"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (TraditionalChinese, RefreshLabel) => "重新整理"
    (Japanese, RefreshLabel) => "更新"
    (English, RunLog) => "Run log"
    (Spanish, RunLog) => "Registro de ejecución"
    (SimplifiedChinese, RunLog) => "运行日志"
    (TraditionalChinese, RunLog) => "執行日誌"
    (Japanese, RunLog) => "実行ログ"
    (English, CloseLog) => "Close log"
    (Spanish, CloseLog) => "Cerrar registro"
    (SimplifiedChinese, CloseLog) => "关闭日志"
    (TraditionalChinese, CloseLog) => "關閉日誌"
    (Japanese, CloseLog) => "ログを閉じる"
    (English, AutomaticallyCreate) => "Automatically create"
    (Spanish, AutomaticallyCreate) => "Crear automáticamente"
    (SimplifiedChinese, AutomaticallyCreate) => "自动创建"
    (TraditionalChinese, AutomaticallyCreate) => "自動建立"
    (Japanese, AutomaticallyCreate) => "自動作成"
    (English, EditSchedule) => "Edit schedule"
    (Spanish, EditSchedule) => "Editar programación"
    (SimplifiedChinese, EditSchedule) => "编辑计划"
    (TraditionalChinese, EditSchedule) => "編輯計劃"
    (Japanese, EditSchedule) => "スケジュールを編集"
    (English, NameLabel) => "Name"
    (Spanish, NameLabel) => "Nombre"
    (SimplifiedChinese, NameLabel) => "名称"
    (TraditionalChinese, NameLabel) => "名稱"
    (Japanese, NameLabel) => "名前"
    (English, WorkingDirectory) => "Working directory"
    (Spanish, WorkingDirectory) => "Directorio de trabajo"
    (SimplifiedChinese, WorkingDirectory) => "工作目录"
    (TraditionalChinese, WorkingDirectory) => "工作目錄"
    (Japanese, WorkingDirectory) => "作業ディレクトリ"
    (English, AutomaticDirectoryDescription) =>
      "OpenSeek creates a dedicated folder on the first run and reuses it to save this task's files and results."
    (Spanish, AutomaticDirectoryDescription) =>
      "OpenSeek crea una carpeta dedicada en la primera ejecución y la reutiliza para guardar los archivos y resultados de esta tarea."
    (SimplifiedChinese, AutomaticDirectoryDescription) =>
      "OpenSeek 会在首次运行时创建专用文件夹，并继续用它保存此任务的文件和结果。"
    (TraditionalChinese, AutomaticDirectoryDescription) =>
      "OpenSeek 會在首次執行時建立專用資料夾，並繼續用它儲存此任務的檔案和結果。"
    (Japanese, AutomaticDirectoryDescription) =>
      "OpenSeek は初回実行時に専用フォルダーを作成し、以降もタスクのファイルと結果の保存に使用します。"
    (English, ProjectDirectoryDescription) =>
      "This task runs in the selected project folder and can read and update its files."
    (Spanish, ProjectDirectoryDescription) =>
      "Esta tarea se ejecuta en la carpeta del proyecto seleccionado y puede leer y actualizar sus archivos."
    (SimplifiedChinese, ProjectDirectoryDescription) =>
      "此任务在所选项目文件夹中运行，可读取和更新其中的文件。"
    (TraditionalChinese, ProjectDirectoryDescription) =>
      "此任務在所選專案資料夾中執行，可讀取和更新其中的檔案。"
    (Japanese, ProjectDirectoryDescription) =>
      "このタスクは選択したプロジェクトフォルダーで実行され、その中のファイルを読み取り・更新できます。"
    (English, TaskLabel) => "Task"
    (Spanish, TaskLabel) => "Tarea"
    (SimplifiedChinese, TaskLabel) => "任务"
    (TraditionalChinese, TaskLabel) => "任務"
    (Japanese, TaskLabel) => "タスク"
    (English, ScheduleLabel) => "Schedule"
    (Spanish, ScheduleLabel) => "Programación"
    (SimplifiedChinese, ScheduleLabel) => "计划"
    (TraditionalChinese, ScheduleLabel) => "計劃"
    (Japanese, ScheduleLabel) => "スケジュール"
    (English, EveryLabel) => "Every"
    (Spanish, EveryLabel) => "Cada"
    (SimplifiedChinese, EveryLabel) => "每隔"
    (TraditionalChinese, EveryLabel) => "每隔"
    (Japanese, EveryLabel) => "定期実行"
    (English, OnceIn) => "Once, in"
    (Spanish, OnceIn) => "Una vez, en"
    (SimplifiedChinese, OnceIn) => "延迟执行一次"
    (TraditionalChinese, OnceIn) => "延遲執行一次"
    (Japanese, OnceIn) => "指定時間後に一度実行"
    (English, MinutesLabel) => "Minutes"
    (Spanish, MinutesLabel) => "Minutos"
    (SimplifiedChinese, MinutesLabel) => "分钟"
    (TraditionalChinese, MinutesLabel) => "分鐘"
    (Japanese, MinutesLabel) => "分"
    (English, TimeoutMinutes) => "Timeout (minutes)"
    (Spanish, TimeoutMinutes) => "Tiempo de espera (minutos)"
    (SimplifiedChinese, TimeoutMinutes) => "超时时间（分钟）"
    (TraditionalChinese, TimeoutMinutes) => "逾時時間（分鐘）"
    (Japanese, TimeoutMinutes) => "タイムアウト（分）"
    (English, ModelDefault) => "Model (blank uses host default)"
    (Spanish, ModelDefault) =>
      "Modelo (vacío para usar el predeterminado del host)"
    (SimplifiedChinese, ModelDefault) =>
      "模型（留空使用主机默认值）"
    (TraditionalChinese, ModelDefault) =>
      "模型（留空使用主機預設值）"
    (Japanese, ModelDefault) =>
      "モデル（空欄でホストの既定値を使用）"
    (English, SchedulePermissions) =>
      "Uses this host's API settings. Permission escalation is refused in unattended runs."
    (Spanish, SchedulePermissions) =>
      "Usa la configuración de API de este host. No se permite ampliar permisos en ejecuciones desatendidas."
    (SimplifiedChinese, SchedulePermissions) =>
      "使用此主机的 API 设置。无人值守运行时不允许提升权限。"
    (TraditionalChinese, SchedulePermissions) =>
      "使用此主機的 API 設定。無人值守執行時不允許提升許可權。"
    (Japanese, SchedulePermissions) =>
      "このホストの API 設定を使用します。無人実行時の権限昇格は許可されません。"
    (English, RunNowDescription) =>
      "Save and run now executes once immediately without changing the schedule."
    (Spanish, RunNowDescription) =>
      "Guardar y ejecutar ahora ejecuta la tarea una vez de inmediato sin cambiar la programación."
    (SimplifiedChinese, RunNowDescription) =>
      "“保存并立即运行”会立即执行一次，不改变计划时间。"
    (TraditionalChinese, RunNowDescription) =>
      "“儲存並立即執行”會立即執行一次，不改變計劃時間。"
    (Japanese, RunNowDescription) =>
      "「保存して今すぐ実行」はスケジュール時刻を変更せず、一度実行します。"
    (English, SaveRunNow) => "Save and run now"
    (Spanish, SaveRunNow) => "Guardar y ejecutar ahora"
    (SimplifiedChinese, SaveRunNow) => "保存并立即运行"
    (TraditionalChinese, SaveRunNow) => "儲存並立即執行"
    (Japanese, SaveRunNow) => "保存して今すぐ実行"
    (English, SaveSchedule) => "Save schedule"
    (Spanish, SaveSchedule) => "Guardar programación"
    (SimplifiedChinese, SaveSchedule) => "保存计划"
    (TraditionalChinese, SaveSchedule) => "儲存計劃"
    (Japanese, SaveSchedule) => "スケジュールを保存"
    (English, CancelLabel) => "Cancel"
    (Spanish, CancelLabel) => "Cancelar"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, EmptySchedules) =>
      "No schedules yet. Create one to run a task later or at a fixed interval."
    (Spanish, EmptySchedules) =>
      "Aún no hay programaciones. Crea una para ejecutar una tarea más tarde o a intervalos fijos."
    (SimplifiedChinese, EmptySchedules) =>
      "尚无定时计划。创建计划，让任务稍后执行或定期运行。"
    (TraditionalChinese, EmptySchedules) =>
      "尚無定時計劃。建立計劃，讓任務稍後執行或定期執行。"
    (Japanese, EmptySchedules) =>
      "スケジュールがありません。タスクを後で、または定期的に実行するスケジュールを作成してください。"
    (English, OnceLabel) => "Once · "
    (Spanish, OnceLabel) => "Una vez · "
    (SimplifiedChinese, OnceLabel) => "一次 · "
    (TraditionalChinese, OnceLabel) => "一次 · "
    (Japanese, OnceLabel) => "一度 · "
    (English, NextLabel) => "Next: "
    (Spanish, NextLabel) => "Próxima: "
    (SimplifiedChinese, NextLabel) => "下次："
    (TraditionalChinese, NextLabel) => "下次："
    (Japanese, NextLabel) => "次回："
    (English, WaitingLabel) => "Waiting"
    (Spanish, WaitingLabel) => "En espera"
    (SimplifiedChinese, WaitingLabel) => "等待中"
    (TraditionalChinese, WaitingLabel) => "等待中"
    (Japanese, WaitingLabel) => "待機中"
    (English, PausedStatus) => "Paused"
    (Spanish, PausedStatus) => "En pausa"
    (SimplifiedChinese, PausedStatus) => "已暂停"
    (TraditionalChinese, PausedStatus) => "已暫停"
    (Japanese, PausedStatus) => "一時停止中"
    (English, FinishedStatus) => "Finished"
    (Spanish, FinishedStatus) => "Finalizado"
    (SimplifiedChinese, FinishedStatus) => "已结束"
    (TraditionalChinese, FinishedStatus) => "已結束"
    (Japanese, FinishedStatus) => "終了"
    (English, QueuedLabel) => "Queued"
    (Spanish, QueuedLabel) => "En cola"
    (SimplifiedChinese, QueuedLabel) => "已排队"
    (TraditionalChinese, QueuedLabel) => "已排隊"
    (Japanese, QueuedLabel) => "待機中"
    (English, AutomaticDirectory) => "Automatically created working directory"
    (Spanish, AutomaticDirectory) =>
      "Directorio de trabajo creado automáticamente"
    (SimplifiedChinese, AutomaticDirectory) => "自动创建的工作目录"
    (TraditionalChinese, AutomaticDirectory) => "自動建立的工作目錄"
    (Japanese, AutomaticDirectory) =>
      "自動作成された作業ディレクトリ"
    (English, RunNow) => "Run now"
    (Spanish, RunNow) => "Ejecutar ahora"
    (SimplifiedChinese, RunNow) => "立即运行"
    (TraditionalChinese, RunNow) => "立即執行"
    (Japanese, RunNow) => "今すぐ実行"
    (English, PauseLabel) => "Pause"
    (Spanish, PauseLabel) => "Pausar"
    (SimplifiedChinese, PauseLabel) => "暂停"
    (TraditionalChinese, PauseLabel) => "暫停"
    (Japanese, PauseLabel) => "一時停止"
    (English, ResumeLabel) => "Resume"
    (Spanish, ResumeLabel) => "Reanudar"
    (SimplifiedChinese, ResumeLabel) => "继续"
    (TraditionalChinese, ResumeLabel) => "繼續"
    (Japanese, ResumeLabel) => "再開"
    (English, EditLabel) => "Edit"
    (Spanish, EditLabel) => "Editar"
    (SimplifiedChinese, EditLabel) => "编辑"
    (TraditionalChinese, EditLabel) => "編輯"
    (Japanese, EditLabel) => "編集"
    (English, StopRun) => "Stop run"
    (Spanish, StopRun) => "Detener ejecución"
    (SimplifiedChinese, StopRun) => "停止运行"
    (TraditionalChinese, StopRun) => "停止執行"
    (Japanese, StopRun) => "実行を停止"
    (English, DeleteLabel) => "Delete"
    (Spanish, DeleteLabel) => "Eliminar"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (TraditionalChinese, DeleteLabel) => "刪除"
    (Japanese, DeleteLabel) => "削除"
    (English, RunHistory) => "Run history"
    (Spanish, RunHistory) => "Historial de ejecuciones"
    (SimplifiedChinese, RunHistory) => "运行历史"
    (TraditionalChinese, RunHistory) => "執行歷史"
    (Japanese, RunHistory) => "実行履歴"
    (English, NoRunningTasks) => "No tasks are running."
    (Spanish, NoRunningTasks) => "No hay tareas en ejecución."
    (SimplifiedChinese, NoRunningTasks) => "没有正在运行的任务。"
    (TraditionalChinese, NoRunningTasks) => "沒有正在執行的任務。"
    (Japanese, NoRunningTasks) => "実行中のタスクはありません。"
    (English, NoFinishedRuns) => "No finished runs yet."
    (Spanish, NoFinishedRuns) => "Aún no hay ejecuciones finalizadas."
    (SimplifiedChinese, NoFinishedRuns) => "尚无已结束的运行记录。"
    (TraditionalChinese, NoFinishedRuns) => "尚無已結束的執行記錄。"
    (Japanese, NoFinishedRuns) =>
      "終了した実行履歴はまだありません。"
    (English, OpenSession) => "Open session"
    (Spanish, OpenSession) => "Abrir sesión"
    (SimplifiedChinese, OpenSession) => "打开会话"
    (TraditionalChinese, OpenSession) => "開啟會話"
    (Japanese, OpenSession) => "セッションを開く"
    (English, ViewLog) => "View log"
    (Spanish, ViewLog) => "Ver registro"
    (SimplifiedChinese, ViewLog) => "查看日志"
    (TraditionalChinese, ViewLog) => "檢視日誌"
    (Japanese, ViewLog) => "ログを表示"
    (English, LogLabel) => "Log: "
    (Spanish, LogLabel) => "Registro: "
    (SimplifiedChinese, LogLabel) => "日志："
    (TraditionalChinese, LogLabel) => "日誌："
    (Japanese, LogLabel) => "ログ："
    (English, RecordedFailure) => "Recorded failure:"
    (Spanish, RecordedFailure) => "Fallo registrado:"
    (SimplifiedChinese, RecordedFailure) => "已记录的失败："
    (TraditionalChinese, RecordedFailure) => "已記錄的失敗："
    (Japanese, RecordedFailure) => "記録されたエラー："
    (English, LogUnreadable) => "Log could not be read:"
    (Spanish, LogUnreadable) => "No se pudo leer el registro:"
    (SimplifiedChinese, LogUnreadable) => "无法读取日志："
    (TraditionalChinese, LogUnreadable) => "無法讀取日誌："
    (Japanese, LogUnreadable) => "ログを読み取れませんでした："
    (English, SkippedPreviousRunActive) =>
      "Skipped: the previous run was still active"
    (Spanish, SkippedPreviousRunActive) =>
      "Omitido: la ejecución anterior seguía activa"
    (SimplifiedChinese, SkippedPreviousRunActive) =>
      "已跳过：上一次运行仍在进行"
    (TraditionalChinese, SkippedPreviousRunActive) =>
      "已略過：上一次執行仍在進行"
    (Japanese, SkippedPreviousRunActive) =>
      "スキップ：前回の実行がまだ終わっていませんでした"
    (English, SkippedCapacityFull) => "Skipped: all execution slots were busy"
    (Spanish, SkippedCapacityFull) =>
      "Omitido: todas las ranuras de ejecución estaban ocupadas"
    (SimplifiedChinese, SkippedCapacityFull) =>
      "已跳过：所有执行槽位都在使用中"
    (TraditionalChinese, SkippedCapacityFull) =>
      "已略過：所有執行槽位都在使用中"
    (Japanese, SkippedCapacityFull) =>
      "スキップ：すべての実行枠が使用中でした"
    (English, SkippedMissedTime) =>
      "Skipped: the host missed the scheduled time"
    (Spanish, SkippedMissedTime) =>
      "Omitido: el host no llegó a la hora programada"
    (SimplifiedChinese, SkippedMissedTime) =>
      "已跳过：主机错过了计划时间"
    (TraditionalChinese, SkippedMissedTime) =>
      "已略過：主機錯過了計劃時間"
    (Japanese, SkippedMissedTime) =>
      "スキップ：ホストが予定時刻に間に合いませんでした"
    (English, SkippedAutomaticFolderUnavailable) =>
      "Skipped: the host could not prepare this task's automatic folder"
    (Spanish, SkippedAutomaticFolderUnavailable) =>
      "Omitido: el host no pudo preparar el directorio de trabajo creado automáticamente para esta tarea"
    (SimplifiedChinese, SkippedAutomaticFolderUnavailable) =>
      "已跳过：主机无法准备此任务自动创建的工作目录"
    (TraditionalChinese, SkippedAutomaticFolderUnavailable) =>
      "已略過：主機無法準備此任務自動建立的工作目錄"
    (Japanese, SkippedAutomaticFolderUnavailable) =>
      "スキップ：ホストがこのタスクの自動作成された作業ディレクトリを準備できませんでした"
    (English, RefusedForeignOwner) =>
      "Schedules are run by another SeekMoon open on this computer; change them there"
    (Spanish, RefusedForeignOwner) =>
      "Otra instancia de SeekMoon abierta en este equipo ejecuta las programaciones; cámbialas allí"
    (SimplifiedChinese, RefusedForeignOwner) =>
      "计划由这台电脑上另一个打开的 SeekMoon 运行，请在那里修改"
    (TraditionalChinese, RefusedForeignOwner) =>
      "計劃由這台電腦上另一個開啟的 SeekMoon 執行，請在那裡修改"
    (Japanese, RefusedForeignOwner) =>
      "スケジュールはこのコンピューターで開いている別の SeekMoon が実行しています。そちらで変更してください"
    (English, RefusedMissing) => "This schedule no longer exists"
    (Spanish, RefusedMissing) => "Esta programación ya no existe"
    (SimplifiedChinese, RefusedMissing) => "此计划已不存在"
    (TraditionalChinese, RefusedMissing) => "此計劃已不存在"
    (Japanese, RefusedMissing) =>
      "このスケジュールはもう存在しません"
    (English, RefusedUnattachedProject) =>
      "Choose an attached project for this schedule"
    (Spanish, RefusedUnattachedProject) =>
      "Elige un proyecto adjunto para esta programación"
    (SimplifiedChinese, RefusedUnattachedProject) =>
      "请为此计划选择一个已添加的项目"
    (TraditionalChinese, RefusedUnattachedProject) =>
      "請為此計劃選擇一個已加入的專案"
    (Japanese, RefusedUnattachedProject) =>
      "このスケジュールには追加済みのプロジェクトを選んでください"
    (English, RefusedPastTime) =>
      "The scheduled time has passed. Choose a time in the future."
    (Spanish, RefusedPastTime) =>
      "La hora programada ya pasó. Elige una hora futura."
    (SimplifiedChinese, RefusedPastTime) =>
      "计划时间已过，请选择将来的时间。"
    (TraditionalChinese, RefusedPastTime) =>
      "計劃時間已過，請選擇未來的時間。"
    (Japanese, RefusedPastTime) =>
      "予定時刻は過ぎています。これから先の時刻を選んでください。"
    (English, RefusedAlreadyRunning) => "This schedule is already running"
    (Spanish, RefusedAlreadyRunning) =>
      "Esta programación ya se está ejecutando"
    (SimplifiedChinese, RefusedAlreadyRunning) => "此计划正在运行"
    (TraditionalChinese, RefusedAlreadyRunning) => "此計劃正在執行"
    (Japanese, RefusedAlreadyRunning) =>
      "このスケジュールはすでに実行中です"
    (English, RefusedAlreadyQueued) => "This schedule is already queued to run"
    (Spanish, RefusedAlreadyQueued) =>
      "Esta programación ya está en cola para ejecutarse"
    (SimplifiedChinese, RefusedAlreadyQueued) =>
      "此计划已在排队等待运行"
    (TraditionalChinese, RefusedAlreadyQueued) =>
      "此計劃已在排隊等待執行"
    (Japanese, RefusedAlreadyQueued) =>
      "このスケジュールはすでに実行待ちです"
    (English, RefusedStopBeforeDelete) =>
      "Stop this run before deleting its schedule"
    (Spanish, RefusedStopBeforeDelete) =>
      "Detén esta ejecución antes de eliminar su programación"
    (SimplifiedChinese, RefusedStopBeforeDelete) =>
      "请先停止本次运行，再删除其计划"
    (TraditionalChinese, RefusedStopBeforeDelete) =>
      "請先停止本次執行，再刪除其計劃"
    (Japanese, RefusedStopBeforeDelete) =>
      "スケジュールを削除する前に、この実行を停止してください"
  }
}

///|
/// What the page says about a schedule occurrence that did not launch.
fn schedule_skip_text(
  locale : @i18n.Locale,
  skip : @protocol.ScheduleSkip,
) -> String {
  ui(
    locale,
    match skip {
      PreviousRunActive => SkippedPreviousRunActive
      CapacityFull => SkippedCapacityFull
      MissedTime => SkippedMissedTime
      AutomaticFolderUnavailable => SkippedAutomaticFolderUnavailable
    },
  )
}

///|
/// What the page says when the host declines a schedule change.
fn schedule_refusal_text(
  locale : @i18n.Locale,
  refusal : @protocol.ScheduleRefusal,
) -> String {
  ui(
    locale,
    match refusal {
      ForeignOwner => RefusedForeignOwner
      Missing => RefusedMissing
      UnattachedProject => RefusedUnattachedProject
      PastTime => RefusedPastTime
      AlreadyRunning => RefusedAlreadyRunning
      AlreadyQueued => RefusedAlreadyQueued
      StopBeforeDelete => RefusedStopBeforeDelete
    },
  )
}

///|
/// A repeating interval in the largest whole unit that fits it: "Every day",
/// not "Every 1440 min".
fn schedule_interval_text(locale : @i18n.Locale, minutes : Int32) -> String {
  let week = 7 * 24 * 60
  let day = 24 * 60
  if minutes % week == 0 {
    let n = minutes / week
    match (locale, n) {
      (English, 1) => "Every week"
      (English, _) => "Every \{n} weeks"
      (Spanish, 1) => "Cada semana"
      (Spanish, _) => "Cada \{n} semanas"
      (SimplifiedChinese, 1) => "每周"
      (SimplifiedChinese, _) => "每 \{n} 周"
      (TraditionalChinese, 1) => "每週"
      (TraditionalChinese, _) => "每 \{n} 週"
      (Japanese, 1) => "毎週"
      (Japanese, _) => "\{n} 週間ごと"
    }
  } else if minutes % day == 0 {
    let n = minutes / day
    match (locale, n) {
      (English, 1) => "Every day"
      (English, _) => "Every \{n} days"
      (Spanish, 1) => "Cada día"
      (Spanish, _) => "Cada \{n} días"
      (SimplifiedChinese, 1) => "每天"
      (SimplifiedChinese, _) => "每 \{n} 天"
      (TraditionalChinese, 1) => "每天"
      (TraditionalChinese, _) => "每 \{n} 天"
      (Japanese, 1) => "毎日"
      (Japanese, _) => "\{n} 日ごと"
    }
  } else if minutes % 60 == 0 {
    let n = minutes / 60
    match (locale, n) {
      (English, 1) => "Every hour"
      (English, _) => "Every \{n} hours"
      (Spanish, 1) => "Cada hora"
      (Spanish, _) => "Cada \{n} horas"
      (SimplifiedChinese, 1) => "每小时"
      (SimplifiedChinese, _) => "每 \{n} 小时"
      (TraditionalChinese, 1) => "每小時"
      (TraditionalChinese, _) => "每 \{n} 小時"
      (Japanese, 1) => "1 時間ごと"
      (Japanese, _) => "\{n} 時間ごと"
    }
  } else {
    match locale {
      English => "Every \{minutes} min"
      Spanish => "Cada \{minutes} min"
      SimplifiedChinese => "每 \{minutes} 分钟"
      TraditionalChinese => "每 \{minutes} 分鐘"
      Japanese => "\{minutes} 分ごと"
    }
  }
}

///|
/// The question a schedule card asks before deleting it. The host keeps the
/// schedule's run history and working folder.
fn schedule_delete_question(locale : @i18n.Locale, name : String) -> String {
  match locale {
    English =>
      "Delete “\{name}”? Its run history and working folder are kept."
    Spanish =>
      "¿Eliminar «\{name}»? Se conservan su historial de ejecuciones y su carpeta de trabajo."
    SimplifiedChinese =>
      "删除“\{name}”？其运行记录和工作目录会保留。"
    TraditionalChinese =>
      "刪除「\{name}」？其執行記錄和工作目錄會保留。"
    Japanese =>
      "「\{name}」を削除しますか？実行履歴と作業ディレクトリは残ります。"
  }
}
