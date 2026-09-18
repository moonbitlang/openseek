// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  NewTab
  JobsLabel
  JobsHint
  WorkflowsLabel
  WorkflowsHint
  ReviewChanges
  ReviewHint
  SearchLabel
  SearchHint
  OpenFile
  OpenFileHint
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, NewTab) => "New Tab"
    (SimplifiedChinese, NewTab) => "新建标签页"
    (Japanese, NewTab) => "新しいタブ"
    (English, JobsLabel) => "Jobs"
    (SimplifiedChinese, JobsLabel) => "后台任务"
    (Japanese, JobsLabel) => "バックグラウンドジョブ"
    (English, JobsHint) => "Background jobs and retained output"
    (SimplifiedChinese, JobsHint) => "后台任务及保留的输出"
    (Japanese, JobsHint) =>
      "バックグラウンドジョブと保存された出力"
    (English, WorkflowsLabel) => "Workflows"
    (SimplifiedChinese, WorkflowsLabel) => "工作流"
    (Japanese, WorkflowsLabel) => "ワークフロー"
    (English, WorkflowsHint) => "Subagents this conversation delegated to"
    (SimplifiedChinese, WorkflowsHint) => "此对话委派的子智能体"
    (Japanese, WorkflowsHint) => "このチャットのサブエージェント"
    (English, ReviewChanges) => "Review Changes"
    (SimplifiedChinese, ReviewChanges) => "审阅更改"
    (Japanese, ReviewChanges) => "変更をレビュー"
    (English, ReviewHint) => "Review changed files and diffs"
    (SimplifiedChinese, ReviewHint) => "审阅文件更改和差异"
    (Japanese, ReviewHint) => "ファイルの変更と差分をレビュー"
    (English, SearchLabel) => "Search"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (Japanese, SearchLabel) => "検索"
    (English, SearchHint) => "Search across files"
    (SimplifiedChinese, SearchHint) => "跨文件搜索"
    (Japanese, SearchHint) => "ファイルを横断検索"
    (English, OpenFile) => "Open File"
    (SimplifiedChinese, OpenFile) => "打开文件"
    (Japanese, OpenFile) => "ファイルを開く"
    (English, OpenFileHint) => "Open a workspace file"
    (SimplifiedChinese, OpenFileHint) => "打开工作区文件"
    (Japanese, OpenFileHint) => "ワークスペースのファイルを開く"
  }
}
