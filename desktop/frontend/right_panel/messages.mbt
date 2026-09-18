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
    (TraditionalChinese, NewTab) => "新建標籤頁"
    (Japanese, NewTab) => "新しいタブ"
    (English, JobsLabel) => "Jobs"
    (SimplifiedChinese, JobsLabel) => "后台任务"
    (TraditionalChinese, JobsLabel) => "後臺任務"
    (Japanese, JobsLabel) => "バックグラウンドジョブ"
    (English, JobsHint) => "Background jobs and retained output"
    (SimplifiedChinese, JobsHint) => "后台任务及保留的输出"
    (TraditionalChinese, JobsHint) => "後臺任務及保留的輸出"
    (Japanese, JobsHint) =>
      "バックグラウンドジョブと保存された出力"
    (English, WorkflowsLabel) => "Workflows"
    (SimplifiedChinese, WorkflowsLabel) => "工作流"
    (TraditionalChinese, WorkflowsLabel) => "工作流"
    (Japanese, WorkflowsLabel) => "ワークフロー"
    (English, WorkflowsHint) => "Subagents this conversation delegated to"
    (SimplifiedChinese, WorkflowsHint) => "此对话委派的子智能体"
    (TraditionalChinese, WorkflowsHint) => "此對話委派的子代理程式"
    (Japanese, WorkflowsHint) => "このチャットのサブエージェント"
    (English, ReviewChanges) => "Review Changes"
    (SimplifiedChinese, ReviewChanges) => "审阅更改"
    (TraditionalChinese, ReviewChanges) => "審閱更改"
    (Japanese, ReviewChanges) => "変更をレビュー"
    (English, ReviewHint) => "Review changed files and diffs"
    (SimplifiedChinese, ReviewHint) => "审阅文件更改和差异"
    (TraditionalChinese, ReviewHint) => "審閱檔案更改和差異"
    (Japanese, ReviewHint) => "ファイルの変更と差分をレビュー"
    (English, SearchLabel) => "Search"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (TraditionalChinese, SearchLabel) => "搜尋"
    (Japanese, SearchLabel) => "検索"
    (English, SearchHint) => "Search across files"
    (SimplifiedChinese, SearchHint) => "跨文件搜索"
    (TraditionalChinese, SearchHint) => "跨檔案搜尋"
    (Japanese, SearchHint) => "ファイルを横断検索"
    (English, OpenFile) => "Open File"
    (SimplifiedChinese, OpenFile) => "打开文件"
    (TraditionalChinese, OpenFile) => "開啟檔案"
    (Japanese, OpenFile) => "ファイルを開く"
    (English, OpenFileHint) => "Open a workspace file"
    (SimplifiedChinese, OpenFileHint) => "打开工作区文件"
    (TraditionalChinese, OpenFileHint) => "開啟工作區檔案"
    (Japanese, OpenFileHint) => "ワークスペースのファイルを開く"
  }
}
