// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum UiMessage {
  Servers
  Description
  Refresh
  Refreshing
  NoConversation
  CodexConversation
  EngineStopped
  EngineConnecting
  NotConfigured
  NoServers
  ConfigFailed(String)
  CheckFailed
  Connected
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
    (English, Servers) => "Servers"
    (Spanish, Servers) => "Servidores"
    (SimplifiedChinese, Servers) => "服务器"
    (TraditionalChinese, Servers) => "伺服器"
    (Japanese, Servers) => "サーバー"
    (English, Description) =>
      "What this conversation's engine is connected to. Edits to mcp.json apply from its next message."
    (Spanish, Description) =>
      "A qué está conectado el motor de esta conversación. Los cambios en mcp.json se aplican a partir de su siguiente mensaje."
    (SimplifiedChinese, Description) =>
      "当前对话的引擎连接的服务器。对 mcp.json 的修改从下一条消息起生效。"
    (TraditionalChinese, Description) =>
      "目前對話的引擎連線的伺服器。對 mcp.json 的修改從下一則訊息起生效。"
    (Japanese, Description) =>
      "この会話のエンジンが接続しているサーバーです。mcp.json の変更は次のメッセージから適用されます。"
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
    (English, CodexConversation) =>
      "Codex conversations take their MCP servers from Codex's own config.toml."
    (Spanish, CodexConversation) =>
      "Las conversaciones de Codex toman sus servidores MCP del config.toml propio de Codex."
    (SimplifiedChinese, CodexConversation) =>
      "Codex 对话使用 Codex 自己的 config.toml 中配置的 MCP 服务器。"
    (TraditionalChinese, CodexConversation) =>
      "Codex 對話使用 Codex 自己的 config.toml 中設定的 MCP 伺服器。"
    (Japanese, CodexConversation) =>
      "Codex の会話は、Codex 自身の config.toml の MCP サーバーを使用します。"
    (English, EngineStopped) =>
      "This conversation's engine is not running. Its servers connect when its next message starts one."
    (Spanish, EngineStopped) =>
      "El motor de esta conversación no está en ejecución. Sus servidores se conectan cuando su siguiente mensaje inicie uno."
    (SimplifiedChinese, EngineStopped) =>
      "此对话的引擎尚未运行。发送下一条消息启动引擎时，会连接它的服务器。"
    (TraditionalChinese, EngineStopped) =>
      "此對話的引擎尚未執行。傳送下一則訊息啟動引擎時，會連線它的伺服器。"
    (Japanese, EngineStopped) =>
      "この会話のエンジンは実行されていません。次のメッセージでエンジンが起動すると、サーバーに接続します。"
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
    (English, NotConfigured) =>
      "This conversation's engine started without an MCP configuration."
    (Spanish, NotConfigured) =>
      "El motor de esta conversación se inició sin configuración de MCP."
    (SimplifiedChinese, NotConfigured) =>
      "此对话的引擎启动时没有 MCP 配置。"
    (TraditionalChinese, NotConfigured) =>
      "此對話的引擎啟動時沒有 MCP 設定。"
    (Japanese, NotConfigured) =>
      "この会話のエンジンは MCP 設定なしで起動しました。"
    (English, NoServers) => "The configuration lists no servers."
    (Spanish, NoServers) => "La configuración no contiene ningún servidor."
    (SimplifiedChinese, NoServers) => "配置中没有任何服务器。"
    (TraditionalChinese, NoServers) => "設定中沒有任何伺服器。"
    (Japanese, NoServers) => "設定にサーバーがありません。"
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
