// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum UiMessage {
  Checking
  ToolCount(Int32)
  EngineStopped
  EngineConnecting
  NotConfigured
  CheckFailed
  NoTools
  NoToolsReason
  Failed
  Lost
  LostReason
  Skipped
  SkippedReason
  NotRunning
  ConnectedCount(Int32)
  FailedCount(Int32)
}

///|
fn text(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, Checking) => "Checking…"
    (Spanish, Checking) => "Comprobando…"
    (SimplifiedChinese, Checking) => "正在读取…"
    (TraditionalChinese, Checking) => "正在讀取…"
    (Japanese, Checking) => "確認中…"
    (English, ToolCount(1)) => "1 tool"
    (English, ToolCount(count)) => "\{count} tools"
    (Spanish, ToolCount(1)) => "1 herramienta"
    (Spanish, ToolCount(count)) => "\{count} herramientas"
    (SimplifiedChinese, ToolCount(count)) => "\{count} 个工具"
    (TraditionalChinese, ToolCount(count)) => "\{count} 個工具"
    (Japanese, ToolCount(count)) => "\{count} 個のツール"
    (English, NotRunning) => "Not running"
    (Spanish, NotRunning) => "No está en ejecución"
    (SimplifiedChinese, NotRunning) => "引擎未运行"
    (TraditionalChinese, NotRunning) => "引擎未執行"
    (Japanese, NotRunning) => "停止中"
    (English, ConnectedCount(count)) => "\{count} connected"
    (Spanish, ConnectedCount(1)) => "1 conectado"
    (Spanish, ConnectedCount(count)) => "\{count} conectados"
    (SimplifiedChinese, ConnectedCount(count)) => "已连接 \{count} 个"
    (TraditionalChinese, ConnectedCount(count)) => "已連線 \{count} 個"
    (Japanese, ConnectedCount(count)) => "\{count} 件接続済み"
    (English, FailedCount(count)) => "\{count} failed"
    (Spanish, FailedCount(1)) => "1 con error"
    (Spanish, FailedCount(count)) => "\{count} con error"
    (SimplifiedChinese, FailedCount(count)) => "\{count} 个失败"
    (TraditionalChinese, FailedCount(count)) => "\{count} 個失敗"
    (Japanese, FailedCount(count)) => "\{count} 件失敗"
    (English, EngineStopped) =>
      "Not running. Servers connect with the next message."
    (Spanish, EngineStopped) =>
      "No está en ejecución. Los servidores se conectan con el siguiente mensaje."
    (SimplifiedChinese, EngineStopped) =>
      "引擎未运行，发送下一条消息时连接。"
    (TraditionalChinese, EngineStopped) =>
      "引擎未執行，傳送下一則訊息時連線。"
    (Japanese, EngineStopped) =>
      "エンジンは停止中です。次のメッセージで接続します。"
    (English, EngineConnecting) => "Connecting…"
    (Spanish, EngineConnecting) => "Conectando…"
    (SimplifiedChinese, EngineConnecting) => "正在连接…"
    (TraditionalChinese, EngineConnecting) => "正在連線…"
    (Japanese, EngineConnecting) => "接続中…"
    (English, NotConfigured) => "No MCP servers configured."
    (Spanish, NotConfigured) => "No hay servidores MCP configurados."
    (SimplifiedChinese, NotConfigured) => "没有配置 MCP 服务器。"
    (TraditionalChinese, NotConfigured) => "沒有設定 MCP 伺服器。"
    (Japanese, NotConfigured) =>
      "MCP サーバーは設定されていません。"
    (English, CheckFailed) => "The status could not be read"
    (Spanish, CheckFailed) => "No se pudo leer el estado"
    (SimplifiedChinese, CheckFailed) => "未能读取状态"
    (TraditionalChinese, CheckFailed) => "未能讀取狀態"
    (Japanese, CheckFailed) => "状態を読み取れませんでした"
    (English, NoTools) => "No tools"
    (Spanish, NoTools) => "Sin herramientas"
    (SimplifiedChinese, NoTools) => "没有工具"
    (TraditionalChinese, NoTools) => "沒有工具"
    (Japanese, NoTools) => "ツールなし"
    (English, NoToolsReason) => "The server connected and offers no tools."
    (Spanish, NoToolsReason) =>
      "El servidor se conectó y no ofrece herramientas."
    (SimplifiedChinese, NoToolsReason) =>
      "服务器已连接，但没有提供任何工具。"
    (TraditionalChinese, NoToolsReason) =>
      "伺服器已連線，但沒有提供任何工具。"
    (Japanese, NoToolsReason) =>
      "サーバーに接続しましたが、ツールは提供されていません。"
    (English, Failed) => "Failed"
    (Spanish, Failed) => "Error"
    (SimplifiedChinese, Failed) => "失败"
    (TraditionalChinese, Failed) => "失敗"
    (Japanese, Failed) => "失敗"
    (English, Lost) => "Disconnected"
    (Spanish, Lost) => "Desconectado"
    (SimplifiedChinese, Lost) => "已断开"
    (TraditionalChinese, Lost) => "已中斷"
    (Japanese, Lost) => "切断"
    (English, LostReason) =>
      "Exited or dropped the connection after connecting. Its tools fail until the engine restarts."
    (Spanish, LostReason) =>
      "El servidor se conectó y después terminó o perdió la conexión. Sus herramientas fallan hasta que el motor se reinicie."
    (SimplifiedChinese, LostReason) =>
      "服务器曾经连接成功，之后退出或断开了连接。在引擎重启之前，它的工具调用都会失败。"
    (TraditionalChinese, LostReason) =>
      "伺服器曾經連線成功，之後結束或中斷了連線。在引擎重新啟動之前，它的工具呼叫都會失敗。"
    (Japanese, LostReason) =>
      "サーバーは接続後に終了したか、接続が切れました。エンジンが再起動するまで、そのツールは失敗します。"
    (English, Skipped) => "Skipped"
    (Spanish, Skipped) => "Omitido"
    (SimplifiedChinese, Skipped) => "已跳过"
    (TraditionalChinese, Skipped) => "已略過"
    (Japanese, Skipped) => "スキップ"
    (English, SkippedReason) =>
      "Not started: the servers before it already reached the tool limit."
    (Spanish, SkippedReason) =>
      "No se inició: los servidores anteriores ya alcanzaron el límite de herramientas."
    (SimplifiedChinese, SkippedReason) =>
      "未启动：排在前面的服务器已经用完了工具数量上限。"
    (TraditionalChinese, SkippedReason) =>
      "未啟動：排在前面的伺服器已經用完了工具數量上限。"
    (Japanese, SkippedReason) =>
      "起動していません。先のサーバーでツール数の上限に達しました。"
  }
}
