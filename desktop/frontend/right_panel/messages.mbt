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
    (English, JobsLabel) => "Jobs"
    (SimplifiedChinese, JobsLabel) => "后台任务"
    (English, JobsHint) => "Background jobs and retained output"
    (SimplifiedChinese, JobsHint) => "后台任务及保留的输出"
    (English, WorkflowsLabel) => "Workflows"
    (SimplifiedChinese, WorkflowsLabel) => "工作流"
    (English, WorkflowsHint) => "Subagents this conversation delegated to"
    (SimplifiedChinese, WorkflowsHint) => "此对话委派的子智能体"
    (English, ReviewChanges) => "Review Changes"
    (SimplifiedChinese, ReviewChanges) => "审阅更改"
    (English, ReviewHint) => "Review changed files and diffs"
    (SimplifiedChinese, ReviewHint) => "审阅文件更改和差异"
    (English, SearchLabel) => "Search"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (English, SearchHint) => "Search across files"
    (SimplifiedChinese, SearchHint) => "跨文件搜索"
    (English, OpenFile) => "Open File"
    (SimplifiedChinese, OpenFile) => "打开文件"
    (English, OpenFileHint) => "Open a workspace file"
    (SimplifiedChinese, OpenFileHint) => "打开工作区文件"
  }
}
