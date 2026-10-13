// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum UiMessage {
  Servers
  Description
  Refresh
  Refreshing
  NoConversation
  EngineNotRunning(String)
  EngineConnecting
  NotConfigured(String)
  NoServers(String)
  ConfigFailed(String)
  CheckFailed
  Connected
  ToolCount(Int32)
  NoTools
  NoToolsReason
  Failed
  Lost
  LostReason
  Skipped
  SkippedReason
}

///|
fn text(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, Servers) => "MCP servers"
    (Spanish, Servers) => "Servidores MCP"
    (SimplifiedChinese, Servers) => "MCP 服务器"
    (TraditionalChinese, Servers) => "MCP 伺服器"
    (Japanese, Servers) => "MCP サーバー"
    (English, Description) =>
      "Servers listed in mcp.json give the agent extra tools. This shows what the current conversation's engine is connected to; edits to the file apply from its next message."
    (Spanish, Description) =>
      "Los servidores indicados en mcp.json dan al agente herramientas adicionales. Aquí se muestra a qué está conectado el motor de la conversación actual; los cambios en el archivo se aplican a partir de su siguiente mensaje."
    (SimplifiedChinese, Description) =>
      "mcp.json 中配置的服务器会为智能体提供额外的工具。这里显示当前对话的引擎实际连接的服务器；对文件的修改从该对话的下一条消息起生效。"
    (TraditionalChinese, Description) =>
      "mcp.json 中設定的伺服器會為代理提供額外的工具。這裡顯示目前對話的引擎實際連線的伺服器；對檔案的修改從該對話的下一則訊息起生效。"
    (Japanese, Description) =>
      "mcp.json に記載したサーバーがエージェントに追加のツールを提供します。ここには現在の会話のエンジンが接続しているサーバーが表示されます。ファイルの変更はその会話の次のメッセージから適用されます。"
    (English, Refresh) => "Refresh"
    (Spanish, Refresh) => "Actualizar"
    (SimplifiedChinese, Refresh) => "刷新"
    (TraditionalChinese, Refresh) => "重新整理"
    (Japanese, Refresh) => "更新"
    (English, Refreshing) => "Refreshing…"
    (Spanish, Refreshing) => "Actualizando…"
    (SimplifiedChinese, Refreshing) => "正在刷新…"
    (TraditionalChinese, Refreshing) => "正在重新整理…"
    (Japanese, Refreshing) => "更新中…"
    (English, NoConversation) =>
      "Open a conversation to see what its engine is connected to."
    (Spanish, NoConversation) =>
      "Abre una conversación para ver a qué está conectado su motor."
    (SimplifiedChinese, NoConversation) =>
      "打开一个对话即可查看它的引擎连接了哪些服务器。"
    (TraditionalChinese, NoConversation) =>
      "開啟一個對話即可查看它的引擎連線了哪些伺服器。"
    (Japanese, NoConversation) =>
      "会話を開くと、そのエンジンが接続しているサーバーを確認できます。"
    (English, EngineNotRunning(path)) =>
      "This conversation's engine is not running. Servers in \{path} connect when its next message starts one."
    (Spanish, EngineNotRunning(path)) =>
      "El motor de esta conversación no está en ejecución. Los servidores de \{path} se conectan cuando su siguiente mensaje inicie uno."
    (SimplifiedChinese, EngineNotRunning(path)) =>
      "此对话的引擎尚未运行。发送下一条消息启动引擎时，会连接 \{path} 中的服务器。"
    (TraditionalChinese, EngineNotRunning(path)) =>
      "此對話的引擎尚未執行。傳送下一則訊息啟動引擎時，會連線 \{path} 中的伺服器。"
    (Japanese, EngineNotRunning(path)) =>
      "この会話のエンジンは実行されていません。次のメッセージでエンジンが起動すると、\{path} のサーバーに接続します。"
    (English, EngineConnecting) =>
      "This conversation's engine is starting and has not finished connecting its servers yet."
    (Spanish, EngineConnecting) =>
      "El motor de esta conversación se está iniciando y aún no ha terminado de conectar sus servidores."
    (SimplifiedChinese, EngineConnecting) =>
      "此对话的引擎正在启动，尚未完成服务器连接。"
    (TraditionalChinese, EngineConnecting) =>
      "此對話的引擎正在啟動，尚未完成伺服器連線。"
    (Japanese, EngineConnecting) =>
      "この会話のエンジンは起動中で、サーバーへの接続がまだ完了していません。"
    (English, NotConfigured(path)) =>
      "This conversation's engine started without an MCP configuration. Servers in \{path} connect from its next message."
    (Spanish, NotConfigured(path)) =>
      "El motor de esta conversación se inició sin configuración de MCP. Los servidores de \{path} se conectan a partir de su siguiente mensaje."
    (SimplifiedChinese, NotConfigured(path)) =>
      "此对话的引擎启动时没有 MCP 配置。\{path} 中的服务器会从它的下一条消息起连接。"
    (TraditionalChinese, NotConfigured(path)) =>
      "此對話的引擎啟動時沒有 MCP 設定。\{path} 中的伺服器會從它的下一則訊息起連線。"
    (Japanese, NotConfigured(path)) =>
      "この会話のエンジンは MCP 設定なしで起動しました。\{path} のサーバーには次のメッセージから接続します。"
    (English, NoServers(path)) => "\{path} lists no servers."
    (Spanish, NoServers(path)) => "\{path} no contiene ningún servidor."
    (SimplifiedChinese, NoServers(path)) =>
      "\{path} 中没有配置任何服务器。"
    (TraditionalChinese, NoServers(path)) =>
      "\{path} 中沒有設定任何伺服器。"
    (Japanese, NoServers(path)) =>
      "\{path} にサーバーがありません。"
    (English, ConfigFailed(path)) => "\{path} could not be loaded"
    (Spanish, ConfigFailed(path)) => "No se pudo cargar \{path}"
    (SimplifiedChinese, ConfigFailed(path)) => "无法加载 \{path}"
    (TraditionalChinese, ConfigFailed(path)) => "無法載入 \{path}"
    (Japanese, ConfigFailed(path)) =>
      "\{path} を読み込めませんでした"
    (English, CheckFailed) => "The status could not be read"
    (Spanish, CheckFailed) => "No se pudo leer el estado"
    (SimplifiedChinese, CheckFailed) => "未能读取状态"
    (TraditionalChinese, CheckFailed) => "未能讀取狀態"
    (Japanese, CheckFailed) => "状態を読み取れませんでした"
    (English, Connected) => "Connected"
    (Spanish, Connected) => "Conectado"
    (SimplifiedChinese, Connected) => "已连接"
    (TraditionalChinese, Connected) => "已連線"
    (Japanese, Connected) => "接続済み"
    (English, ToolCount(1)) => "1 tool"
    (English, ToolCount(count)) => "\{count} tools"
    (Spanish, ToolCount(1)) => "1 herramienta"
    (Spanish, ToolCount(count)) => "\{count} herramientas"
    (SimplifiedChinese, ToolCount(count)) => "\{count} 个工具"
    (TraditionalChinese, ToolCount(count)) => "\{count} 個工具"
    (Japanese, ToolCount(count)) => "\{count} 個のツール"
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
      "The server connected and has since exited or dropped the connection. Its tools fail until the engine restarts."
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
