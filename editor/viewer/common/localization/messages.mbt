// Feature-owned UI messages; both locales are exhaustive.

///|
pub(all) enum Message {
  ReadonlyCode
  ReadonlyMarkdown
  TableOfContents
  ItemSeparator
  ExpandSection
  CollapseSection
  FileComparison
  OriginalFile
  ModifiedFile
  ResizeDiffPanes
  CannotComputeDiff
  InvalidDiff
  EditorContextMenu
  ShowContextMenu
  PeekLabel
  GoDefinition
  PeekDefinition
  GoReferences
  PeekReferences
  NoDefinition
  NoDefinitions
  NoReferences
  CannotOpenDefinition
  CannotOpenReference
  NoPreview
  OriginalSource
  ShowSource
  ShowDocumentation
  CollapseDocumentation
  ExpandDocumentation
  LoadingLabel
  LoadingPreview
  DefinitionsLabel
  ReferencesLabel
  DefinitionPreview
  ReferencePreview
  LoadingDefinitions
  LoadingReferences
  CopyLabel
  NoResults
  AddFeedback
  FeedbackLabel
  CancelFeedback
  CancelLabel
  AddFeedbackBatch
  ApplyFeedbackShortcut
  ApplyFeedback
  CollapseLabel
  ExpandLabel
  AgentReview
  AddToComment
  EditLabel
  RemoveLabel
  ShareComment
  AcceptLabel
  RemoveComment
  DeleteLabel
  AddComment
}

///|
pub fn text(locale : Language, message : Message) -> String {
  match (locale, message) {
    (English, ReadonlyCode) => "Readonly code viewer"
    (SimplifiedChinese, ReadonlyCode) => "只读代码查看器"
    (English, ReadonlyMarkdown) => "Readonly Markdown viewer"
    (SimplifiedChinese, ReadonlyMarkdown) => "只读 Markdown 查看器"
    (English, TableOfContents) => "Table of contents"
    (SimplifiedChinese, TableOfContents) => "目录"
    (English, ItemSeparator) => "MoonBit item separator"
    (SimplifiedChinese, ItemSeparator) => "MoonBit 项目分隔线"
    (English, ExpandSection) => "Expand section"
    (SimplifiedChinese, ExpandSection) => "展开章节"
    (English, CollapseSection) => "Collapse section"
    (SimplifiedChinese, CollapseSection) => "折叠章节"
    (English, FileComparison) => "File comparison"
    (SimplifiedChinese, FileComparison) => "文件比较"
    (English, OriginalFile) => "Original file"
    (SimplifiedChinese, OriginalFile) => "原始文件"
    (English, ModifiedFile) => "Modified file"
    (SimplifiedChinese, ModifiedFile) => "修改后的文件"
    (English, ResizeDiffPanes) => "Resize diff panes"
    (SimplifiedChinese, ResizeDiffPanes) => "调整差异窗格大小"
    (English, CannotComputeDiff) => "Unable to compute this diff."
    (SimplifiedChinese, CannotComputeDiff) => "无法计算此差异。"
    (English, InvalidDiff) => "The diff provider returned an invalid result."
    (SimplifiedChinese, InvalidDiff) =>
      "差异提供程序返回了无效结果。"
    (English, EditorContextMenu) => "Editor Context Menu"
    (SimplifiedChinese, EditorContextMenu) => "编辑器上下文菜单"
    (English, ShowContextMenu) => "Show Editor Context Menu"
    (SimplifiedChinese, ShowContextMenu) => "显示编辑器上下文菜单"
    (English, PeekLabel) => "Peek"
    (SimplifiedChinese, PeekLabel) => "速览"
    (English, GoDefinition) => "Go to Definition"
    (SimplifiedChinese, GoDefinition) => "转到定义"
    (English, PeekDefinition) => "Peek Definition"
    (SimplifiedChinese, PeekDefinition) => "速览定义"
    (English, GoReferences) => "Go to References"
    (SimplifiedChinese, GoReferences) => "转到引用"
    (English, PeekReferences) => "Peek References"
    (SimplifiedChinese, PeekReferences) => "速览引用"
    (English, NoDefinition) => "No definition found"
    (SimplifiedChinese, NoDefinition) => "未找到定义"
    (English, NoDefinitions) => "No definitions found"
    (SimplifiedChinese, NoDefinitions) => "未找到定义"
    (English, NoReferences) => "No references found"
    (SimplifiedChinese, NoReferences) => "未找到引用"
    (English, CannotOpenDefinition) => "Unable to open definition"
    (SimplifiedChinese, CannotOpenDefinition) => "无法打开定义"
    (English, CannotOpenReference) => "Unable to open reference"
    (SimplifiedChinese, CannotOpenReference) => "无法打开引用"
    (English, NoPreview) => "No preview available"
    (SimplifiedChinese, NoPreview) => "没有可用的预览"
    (English, OriginalSource) => "Original source"
    (SimplifiedChinese, OriginalSource) => "原始源码"
    (English, ShowSource) => "Show original source"
    (SimplifiedChinese, ShowSource) => "显示原始源码"
    (English, ShowDocumentation) => "Show rendered documentation"
    (SimplifiedChinese, ShowDocumentation) => "显示渲染后的文档"
    (English, CollapseDocumentation) => "Collapse API documentation"
    (SimplifiedChinese, CollapseDocumentation) => "折叠 API 文档"
    (English, ExpandDocumentation) => "Expand API documentation"
    (SimplifiedChinese, ExpandDocumentation) => "展开 API 文档"
    (English, LoadingLabel) => "Loading..."
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (English, LoadingPreview) => "Loading preview…"
    (SimplifiedChinese, LoadingPreview) => "正在加载预览…"
    (English, DefinitionsLabel) => "Definitions"
    (SimplifiedChinese, DefinitionsLabel) => "定义"
    (English, ReferencesLabel) => "References"
    (SimplifiedChinese, ReferencesLabel) => "引用"
    (English, DefinitionPreview) => "Definition preview"
    (SimplifiedChinese, DefinitionPreview) => "定义预览"
    (English, ReferencePreview) => "Reference preview"
    (SimplifiedChinese, ReferencePreview) => "引用预览"
    (English, LoadingDefinitions) => "Loading definitions…"
    (SimplifiedChinese, LoadingDefinitions) => "正在加载定义…"
    (English, LoadingReferences) => "Loading references…"
    (SimplifiedChinese, LoadingReferences) => "正在加载引用…"
    (English, CopyLabel) => "Copy"
    (SimplifiedChinese, CopyLabel) => "复制"
    (English, NoResults) => "No results found"
    (SimplifiedChinese, NoResults) => "未找到结果"
    (English, AddFeedback) => "Add feedback"
    (SimplifiedChinese, AddFeedback) => "添加反馈"
    (English, FeedbackLabel) => "Feedback"
    (SimplifiedChinese, FeedbackLabel) => "反馈"
    (English, CancelFeedback) => "Cancel feedback (Escape)"
    (SimplifiedChinese, CancelFeedback) => "取消反馈（Escape）"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (English, AddFeedbackBatch) => "Add feedback to the batch (Enter)"
    (SimplifiedChinese, AddFeedbackBatch) => "将反馈加入批次（Enter）"
    (English, ApplyFeedbackShortcut) => "Apply all feedback (Alt+Enter)"
    (SimplifiedChinese, ApplyFeedbackShortcut) =>
      "应用所有反馈（Alt+Enter）"
    (English, ApplyFeedback) => "Apply all feedback"
    (SimplifiedChinese, ApplyFeedback) => "应用所有反馈"
    (English, CollapseLabel) => "Collapse"
    (SimplifiedChinese, CollapseLabel) => "折叠"
    (English, ExpandLabel) => "Expand"
    (SimplifiedChinese, ExpandLabel) => "展开"
    (English, AgentReview) => "Agent Review"
    (SimplifiedChinese, AgentReview) => "智能体审阅"
    (English, AddToComment) => "Add to Comment"
    (SimplifiedChinese, AddToComment) => "添加到评论"
    (English, EditLabel) => "Edit"
    (SimplifiedChinese, EditLabel) => "编辑"
    (English, RemoveLabel) => "Remove"
    (SimplifiedChinese, RemoveLabel) => "移除"
    (English, ShareComment) => "Share comment with agent"
    (SimplifiedChinese, ShareComment) => "与智能体分享评论"
    (English, AcceptLabel) => "Accept"
    (SimplifiedChinese, AcceptLabel) => "接受"
    (English, RemoveComment) => "Remove agent comment"
    (SimplifiedChinese, RemoveComment) => "移除智能体评论"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (English, AddComment) => "Add a comment…"
    (SimplifiedChinese, AddComment) => "添加评论…"
  }
}
