// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  EmptyWorkflows
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, EmptyWorkflows) =>
      "No workflows in this conversation yet. A snippet that sets `subrun: true` and runs a workflow will appear here, with a row per subagent."
    (SimplifiedChinese, EmptyWorkflows) =>
      "此对话尚无工作流。设置了 `subrun: true` 并运行工作流的代码片段会显示在这里，每个子智能体占一行。"
    (Japanese, EmptyWorkflows) =>
      "このチャットにはまだワークフローがありません。`subrun: true` を設定してワークフローを実行すると、サブエージェントごとに一行で表示されます。"
  }
}
