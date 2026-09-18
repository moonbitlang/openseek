// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  BrowseLabel
  BrowseHint
  SearchLabel
  SearchHint
  FilesLabel
  FilesHint
  ReviewLabel
  ReviewHint
  WorkflowsLabel
  WorkflowsHint
  JobsLabel
  JobsHint
  CloseLabel
  CloseAllTabs
  NewTab
  RestorePanel
  ExpandPanel
  HidePanel
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, BrowseLabel) => "Browse"
    (SimplifiedChinese, BrowseLabel) => "浏览"
    (English, BrowseHint) => "Open a page in a tab"
    (SimplifiedChinese, BrowseHint) => "在标签页中打开网页"
    (English, SearchLabel) => "Search"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (English, SearchHint) => "Search text across the workspace"
    (SimplifiedChinese, SearchHint) => "在工作区中搜索文本"
    (English, FilesLabel) => "Files"
    (SimplifiedChinese, FilesLabel) => "文件"
    (English, FilesHint) => "Open a file from the workspace"
    (SimplifiedChinese, FilesHint) => "打开工作区中的文件"
    (English, ReviewLabel) => "Review"
    (SimplifiedChinese, ReviewLabel) => "审阅"
    (English, ReviewHint) => "Review changed files and diffs"
    (SimplifiedChinese, ReviewHint) => "审阅文件更改和差异"
    (English, WorkflowsLabel) => "Workflows"
    (SimplifiedChinese, WorkflowsLabel) => "工作流"
    (English, WorkflowsHint) => "Subagents this conversation delegated to"
    (SimplifiedChinese, WorkflowsHint) => "此对话委派的子智能体"
    (English, JobsLabel) => "Jobs"
    (SimplifiedChinese, JobsLabel) => "后台任务"
    (English, JobsHint) => "Follow background commands and their logs"
    (SimplifiedChinese, JobsHint) => "查看后台命令及其日志"
    (English, CloseLabel) => "Close"
    (SimplifiedChinese, CloseLabel) => "关闭"
    (English, CloseAllTabs) => "Close all tabs"
    (SimplifiedChinese, CloseAllTabs) => "关闭所有标签页"
    (English, NewTab) => "New tab"
    (SimplifiedChinese, NewTab) => "新建标签页"
    (English, RestorePanel) => "Restore panel"
    (SimplifiedChinese, RestorePanel) => "还原面板"
    (English, ExpandPanel) => "Expand panel"
    (SimplifiedChinese, ExpandPanel) => "展开面板"
    (English, HidePanel) => "Hide panel"
    (SimplifiedChinese, HidePanel) => "隐藏面板"
  }
}
