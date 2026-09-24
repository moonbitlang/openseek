// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  NewTab
  JobsLabel
  JobsHint
  WorkflowsLabel
  WorkflowsHint
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, NewTab) => "New Tab"
    (Spanish, NewTab) => "Nueva pestaña"
    (SimplifiedChinese, NewTab) => "新建标签页"
    (TraditionalChinese, NewTab) => "新建標籤頁"
    (Japanese, NewTab) => "新しいタブ"
    (English, JobsLabel) => "Jobs"
    (Spanish, JobsLabel) => "Trabajos"
    (SimplifiedChinese, JobsLabel) => "后台任务"
    (TraditionalChinese, JobsLabel) => "後臺任務"
    (Japanese, JobsLabel) => "バックグラウンドジョブ"
    (English, JobsHint) => "Background jobs and retained output"
    (Spanish, JobsHint) => "Trabajos en segundo plano y salida guardada"
    (SimplifiedChinese, JobsHint) => "后台任务及保留的输出"
    (TraditionalChinese, JobsHint) => "後臺任務及保留的輸出"
    (Japanese, JobsHint) =>
      "バックグラウンドジョブと保存された出力"
    (English, WorkflowsLabel) => "Workflows"
    (Spanish, WorkflowsLabel) => "Flujos de trabajo"
    (SimplifiedChinese, WorkflowsLabel) => "工作流"
    (TraditionalChinese, WorkflowsLabel) => "工作流"
    (Japanese, WorkflowsLabel) => "ワークフロー"
    (English, WorkflowsHint) => "Subagents this conversation delegated to"
    (Spanish, WorkflowsHint) =>
      "Subagentes en los que ha delegado esta conversación"
    (SimplifiedChinese, WorkflowsHint) => "此对话委派的子智能体"
    (TraditionalChinese, WorkflowsHint) => "此對話委派的子代理程式"
    (Japanese, WorkflowsHint) => "このチャットのサブエージェント"
  }
}
