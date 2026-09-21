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
    (Spanish, CleanupFailed) => "Falló · limpieza incompleta"
    (SimplifiedChinese, CleanupFailed) => "失败 · 清理未完成"
    (TraditionalChinese, CleanupFailed) => "失敗 · 清理未完成"
    (Japanese, CleanupFailed) => "失敗 · クリーンアップ未完了"
    (English, RunningLabel) => "Running"
    (Spanish, RunningLabel) => "En ejecución"
    (SimplifiedChinese, RunningLabel) => "运行中"
    (TraditionalChinese, RunningLabel) => "執行中"
    (Japanese, RunningLabel) => "実行中"
    (English, StoppingLabel) => "Stopping…"
    (Spanish, StoppingLabel) => "Deteniendo…"
    (SimplifiedChinese, StoppingLabel) => "正在停止…"
    (TraditionalChinese, StoppingLabel) => "正在停止…"
    (Japanese, StoppingLabel) => "停止中…"
    (English, CompletedLabel) => "Completed"
    (Spanish, CompletedLabel) => "Completado"
    (SimplifiedChinese, CompletedLabel) => "已完成"
    (TraditionalChinese, CompletedLabel) => "已完成"
    (Japanese, CompletedLabel) => "完了"
    (English, StoppedLabel) => "Stopped"
    (Spanish, StoppedLabel) => "Detenido"
    (SimplifiedChinese, StoppedLabel) => "已停止"
    (TraditionalChinese, StoppedLabel) => "已停止"
    (Japanese, StoppedLabel) => "停止済み"
    (English, SessionEnded) => "Session ended"
    (Spanish, SessionEnded) => "Sesión terminada"
    (SimplifiedChinese, SessionEnded) => "会话已结束"
    (TraditionalChinese, SessionEnded) => "會話已結束"
    (Japanese, SessionEnded) => "セッション終了"
    (English, OutputLimit) => "Stopped · output limit reached"
    (Spanish, OutputLimit) => "Detenido · límite de salida alcanzado"
    (SimplifiedChinese, OutputLimit) => "已停止 · 达到输出上限"
    (TraditionalChinese, OutputLimit) => "已停止 · 達到輸出上限"
    (Japanese, OutputLimit) => "停止済み · 出力上限に到達"
    (English, TimeLimit) => "Stopped · time limit reached"
    (Spanish, TimeLimit) => "Detenido · límite de tiempo alcanzado"
    (SimplifiedChinese, TimeLimit) => "已停止 · 达到时间上限"
    (TraditionalChinese, TimeLimit) => "已停止 · 達到時間上限"
    (Japanese, TimeLimit) => "停止済み · 時間上限に到達"
    (English, CaptureFailed) => "Stopped · output capture failed"
    (Spanish, CaptureFailed) => "Detenido · fallo al capturar la salida"
    (SimplifiedChinese, CaptureFailed) => "已停止 · 输出捕获失败"
    (TraditionalChinese, CaptureFailed) => "已停止 · 輸出捕獲失敗"
    (Japanese, CaptureFailed) => "停止済み · 出力の取得に失敗"
    (English, InterruptedLabel) => "Interrupted"
    (Spanish, InterruptedLabel) => "Interrumpido"
    (SimplifiedChinese, InterruptedLabel) => "已中断"
    (TraditionalChinese, InterruptedLabel) => "已中斷"
    (Japanese, InterruptedLabel) => "中断済み"
    (English, EndTimeUnavailable) => "End time unavailable"
    (Spanish, EndTimeUnavailable) => "Hora de finalización no disponible"
    (SimplifiedChinese, EndTimeUnavailable) => "结束时间不可用"
    (TraditionalChinese, EndTimeUnavailable) => "結束時間不可用"
    (Japanese, EndTimeUnavailable) => "終了時刻は不明です"
    (English, BackgroundJobs) => "Background jobs"
    (Spanish, BackgroundJobs) => "Trabajos en segundo plano"
    (SimplifiedChinese, BackgroundJobs) => "后台任务"
    (TraditionalChinese, BackgroundJobs) => "後臺任務"
    (Japanese, BackgroundJobs) => "バックグラウンドジョブ"
    (English, RefreshLabel) => "Refresh"
    (Spanish, RefreshLabel) => "Actualizar"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (TraditionalChinese, RefreshLabel) => "重新整理"
    (Japanese, RefreshLabel) => "更新"
    (English, DisconnectedDescription) =>
      "Disconnected. Output remains on the host; reconnect to refresh."
    (Spanish, DisconnectedDescription) =>
      "Desconectado. La salida permanece en el host; vuelve a conectar para actualizar."
    (SimplifiedChinese, DisconnectedDescription) =>
      "连接已断开。输出仍保留在主机上，重新连接后可刷新。"
    (TraditionalChinese, DisconnectedDescription) =>
      "連線已斷開。輸出仍保留在主機上，重新連線後可重新整理。"
    (Japanese, DisconnectedDescription) =>
      "接続が切れました。出力はホストに保持されています。再接続後に更新してください。"
    (English, LoadingJobs) => "Loading jobs…"
    (Spanish, LoadingJobs) => "Cargando trabajos…"
    (SimplifiedChinese, LoadingJobs) => "正在加载后台任务…"
    (TraditionalChinese, LoadingJobs) => "正在載入後臺任務…"
    (Japanese, LoadingJobs) =>
      "バックグラウンドジョブを読み込み中…"
    (English, NoJobs) => "No background jobs yet"
    (Spanish, NoJobs) => "Aún no hay trabajos en segundo plano"
    (SimplifiedChinese, NoJobs) => "尚无后台任务"
    (TraditionalChinese, NoJobs) => "尚無後臺任務"
    (Japanese, NoJobs) => "バックグラウンドジョブはありません"
    (English, JobsDescription) =>
      "Commands appear here when they move to the background. Their output files stay with this conversation."
    (Spanish, JobsDescription) =>
      "Los comandos aparecen aquí al pasar a segundo plano. Sus archivos de salida se guardan con esta conversación."
    (SimplifiedChinese, JobsDescription) =>
      "转入后台的命令会显示在此处。输出文件随此对话保留。"
    (TraditionalChinese, JobsDescription) =>
      "轉入後臺的命令會顯示在此處。輸出檔案隨此對話保留。"
    (Japanese, JobsDescription) =>
      "バックグラウンドに移行したコマンドがここに表示されます。出力ファイルはこのチャットとともに保持されます。"
    (English, HistoryLabel) => "History"
    (Spanish, HistoryLabel) => "Historial"
    (SimplifiedChinese, HistoryLabel) => "历史记录"
    (TraditionalChinese, HistoryLabel) => "歷史記錄"
    (Japanese, HistoryLabel) => "履歴"
    (English, InProgress) => "In progress"
    (Spanish, InProgress) => "En curso"
    (SimplifiedChinese, InProgress) => "进行中"
    (TraditionalChinese, InProgress) => "進行中"
    (Japanese, InProgress) => "進行中"
    (English, LoadOlder) => "Load older jobs"
    (Spanish, LoadOlder) => "Cargar trabajos anteriores"
    (SimplifiedChinese, LoadOlder) => "加载更早的任务"
    (TraditionalChinese, LoadOlder) => "載入更早的任務"
    (Japanese, LoadOlder) => "以前のジョブを読み込む"
    (English, NoOutputLabel) => "No output yet"
    (Spanish, NoOutputLabel) => "Aún no hay salida"
    (SimplifiedChinese, NoOutputLabel) => "尚无输出"
    (TraditionalChinese, NoOutputLabel) => "尚無輸出"
    (Japanese, NoOutputLabel) => "出力はまだありません"
    (English, CopyId) => "Copy job ID"
    (Spanish, CopyId) => "Copiar ID del trabajo"
    (SimplifiedChinese, CopyId) => "复制任务 ID"
    (TraditionalChinese, CopyId) => "複製任務 ID"
    (Japanese, CopyId) => "ジョブ ID をコピー"
    (English, CopyPath) => "Copy path"
    (Spanish, CopyPath) => "Copiar ruta"
    (SimplifiedChinese, CopyPath) => "复制路径"
    (TraditionalChinese, CopyPath) => "複製路徑"
    (Japanese, CopyPath) => "パスをコピー"
    (English, CopyTail) => "Copy tail command"
    (Spanish, CopyTail) => "Copiar comando tail"
    (SimplifiedChinese, CopyTail) => "复制日志跟踪命令"
    (TraditionalChinese, CopyTail) => "複製日誌跟蹤命令"
    (Japanese, CopyTail) => "ログ追跡コマンドをコピー"
    (English, ReloadTail) => "Reload tail"
    (Spanish, ReloadTail) => "Recargar últimas líneas"
    (SimplifiedChinese, ReloadTail) => "重新加载日志末尾"
    (TraditionalChinese, ReloadTail) => "重新載入日誌末尾"
    (Japanese, ReloadTail) => "ログの末尾を再読み込み"
    (English, PauseLabel) => "Pause"
    (Spanish, PauseLabel) => "Pausar"
    (SimplifiedChinese, PauseLabel) => "暂停"
    (TraditionalChinese, PauseLabel) => "暫停"
    (Japanese, PauseLabel) => "一時停止"
    (English, FollowOutput) => "Follow output"
    (Spanish, FollowOutput) => "Seguir salida"
    (SimplifiedChinese, FollowOutput) => "跟踪输出"
    (TraditionalChinese, FollowOutput) => "跟蹤輸出"
    (Japanese, FollowOutput) => "出力を追跡"
    (English, StopJob) => "Stop job"
    (Spanish, StopJob) => "Detener trabajo"
    (SimplifiedChinese, StopJob) => "停止任务"
    (TraditionalChinese, StopJob) => "停止任務"
    (Japanese, StopJob) => "ジョブを停止"
    (English, TruncatedOutput) =>
      "Output capture reached its limit; the retained log is truncated."
    (Spanish, TruncatedOutput) =>
      "La captura de salida alcanzó su límite; el registro guardado está truncado."
    (SimplifiedChinese, TruncatedOutput) =>
      "输出捕获已达上限，保留的日志已截断。"
    (TraditionalChinese, TruncatedOutput) =>
      "輸出捕獲已達上限，保留的日誌已截斷。"
    (Japanese, TruncatedOutput) =>
      "出力の取得上限に達しました。保存されたログは切り詰められています。"
    (English, InvalidUtf8) =>
      "Output contained invalid UTF-8; replacement characters were saved."
    (Spanish, InvalidUtf8) =>
      "La salida contenía UTF-8 no válido; se guardaron caracteres de sustitución."
    (SimplifiedChinese, InvalidUtf8) =>
      "输出包含无效的 UTF-8，已保存为替代字符。"
    (TraditionalChinese, InvalidUtf8) =>
      "輸出包含無效的 UTF-8，已儲存為替代字元。"
    (Japanese, InvalidUtf8) =>
      "出力に無効な UTF-8 が含まれていたため、置換文字で保存されました。"
    (English, NoLogFile) => "No retained log file for this job."
    (Spanish, NoLogFile) =>
      "No hay un archivo de registro guardado para este trabajo."
    (SimplifiedChinese, NoLogFile) => "此任务没有保留的日志文件。"
    (TraditionalChinese, NoLogFile) => "此任務沒有保留的日誌檔案。"
    (Japanese, NoLogFile) =>
      "このジョブには保存されたログファイルがありません。"
    (English, OutputUnavailable) => "Output unavailable · reload to retry."
    (Spanish, OutputUnavailable) =>
      "Salida no disponible · recarga para reintentar."
    (SimplifiedChinese, OutputUnavailable) =>
      "输出不可用 · 重新加载以重试。"
    (TraditionalChinese, OutputUnavailable) =>
      "輸出不可用 · 重新載入以重試。"
    (Japanese, OutputUnavailable) =>
      "出力を取得できません。再読み込みして再試行してください。"
    (English, OutputEnded) => "Output ended"
    (Spanish, OutputEnded) => "Salida finalizada"
    (SimplifiedChinese, OutputEnded) => "输出已结束"
    (TraditionalChinese, OutputEnded) => "輸出已結束"
    (Japanese, OutputEnded) => "出力が終了しました"
    (English, LoadingRemaining) => "Loading remaining output…"
    (Spanish, LoadingRemaining) => "Cargando salida restante…"
    (SimplifiedChinese, LoadingRemaining) => "正在加载剩余输出…"
    (TraditionalChinese, LoadingRemaining) => "正在載入剩餘輸出…"
    (Japanese, LoadingRemaining) => "残りの出力を読み込み中…"
    (English, CatchingUp) => "Catching up with output…"
    (Spanish, CatchingUp) => "Recuperando salida pendiente…"
    (SimplifiedChinese, CatchingUp) => "正在同步输出…"
    (TraditionalChinese, CatchingUp) => "正在同步輸出…"
    (Japanese, CatchingUp) => "出力を同期中…"
    (English, FollowingOutput) => "Following output"
    (Spanish, FollowingOutput) => "Siguiendo salida"
    (SimplifiedChinese, FollowingOutput) => "正在跟踪输出"
    (TraditionalChinese, FollowingOutput) => "正在跟蹤輸出"
    (Japanese, FollowingOutput) => "出力を追跡中"
    (English, PausedOutput) => "Paused · output continues to the file"
    (Spanish, PausedOutput) =>
      "En pausa · la salida sigue guardándose en el archivo"
    (SimplifiedChinese, PausedOutput) => "已暂停 · 输出继续写入文件"
    (TraditionalChinese, PausedOutput) =>
      "已暫停 · 輸出繼續寫入檔案"
    (Japanese, PausedOutput) =>
      "一時停止中 · ファイルへの出力は継続しています"
    (English, JobOutput) => "Job output"
    (Spanish, JobOutput) => "Salida del trabajo"
    (SimplifiedChinese, JobOutput) => "任务输出"
    (TraditionalChinese, JobOutput) => "任務輸出"
    (Japanese, JobOutput) => "ジョブの出力"
    (English, LoadingOutput) => "Loading output…"
    (Spanish, LoadingOutput) => "Cargando salida…"
    (SimplifiedChinese, LoadingOutput) => "正在加载输出…"
    (TraditionalChinese, LoadingOutput) => "正在載入輸出…"
    (Japanese, LoadingOutput) => "出力を読み込み中…"
    (English, NoRetainedOutput) => "No retained output."
    (Spanish, NoRetainedOutput) => "No hay salida guardada."
    (SimplifiedChinese, NoRetainedOutput) => "没有保留的输出。"
    (TraditionalChinese, NoRetainedOutput) => "沒有保留的輸出。"
    (Japanese, NoRetainedOutput) => "保存された出力はありません。"
    (English, NoOutputYet) => "No output yet."
    (Spanish, NoOutputYet) => "Aún no hay salida."
    (SimplifiedChinese, NoOutputYet) => "尚无输出。"
    (TraditionalChinese, NoOutputYet) => "尚無輸出。"
    (Japanese, NoOutputYet) => "出力はまだありません。"
    (English, StopDescription) =>
      "Stop controls the direct process. Logs are retained with the session."
    (Spanish, StopDescription) =>
      "Detener controla el proceso directo. Los registros se conservan con la sesión."
    (SimplifiedChinese, StopDescription) =>
      "停止操作作用于直接进程。日志随会话保留。"
    (TraditionalChinese, StopDescription) =>
      "停止操作作用於直接程序。日誌隨會話保留。"
    (Japanese, StopDescription) =>
      "停止操作は直接のプロセスに適用されます。ログはセッションとともに保持されます。"
  }
}
