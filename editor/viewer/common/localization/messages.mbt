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
    (Japanese, ReadonlyCode) => "読み取り専用コードビューアー"
    (English, ReadonlyMarkdown) => "Readonly Markdown viewer"
    (SimplifiedChinese, ReadonlyMarkdown) => "只读 Markdown 查看器"
    (Japanese, ReadonlyMarkdown) =>
      "読み取り専用 Markdown ビューアー"
    (English, TableOfContents) => "Table of contents"
    (SimplifiedChinese, TableOfContents) => "目录"
    (Japanese, TableOfContents) => "目次"
    (English, ItemSeparator) => "MoonBit item separator"
    (SimplifiedChinese, ItemSeparator) => "MoonBit 项目分隔线"
    (Japanese, ItemSeparator) => "MoonBit 項目の区切り"
    (English, ExpandSection) => "Expand section"
    (SimplifiedChinese, ExpandSection) => "展开章节"
    (Japanese, ExpandSection) => "セクションを展開"
    (English, CollapseSection) => "Collapse section"
    (SimplifiedChinese, CollapseSection) => "折叠章节"
    (Japanese, CollapseSection) => "セクションを折りたたむ"
    (English, FileComparison) => "File comparison"
    (SimplifiedChinese, FileComparison) => "文件比较"
    (Japanese, FileComparison) => "ファイル比較"
    (English, OriginalFile) => "Original file"
    (SimplifiedChinese, OriginalFile) => "原始文件"
    (Japanese, OriginalFile) => "元のファイル"
    (English, ModifiedFile) => "Modified file"
    (SimplifiedChinese, ModifiedFile) => "修改后的文件"
    (Japanese, ModifiedFile) => "変更後のファイル"
    (English, ResizeDiffPanes) => "Resize diff panes"
    (SimplifiedChinese, ResizeDiffPanes) => "调整差异窗格大小"
    (Japanese, ResizeDiffPanes) => "差分ペインのサイズを変更"
    (English, CannotComputeDiff) => "Unable to compute this diff."
    (SimplifiedChinese, CannotComputeDiff) => "无法计算此差异。"
    (Japanese, CannotComputeDiff) => "この差分を計算できません。"
    (English, InvalidDiff) => "The diff provider returned an invalid result."
    (SimplifiedChinese, InvalidDiff) =>
      "差异提供程序返回了无效结果。"
    (Japanese, InvalidDiff) =>
      "差分プロバイダーが無効な結果を返しました。"
    (English, EditorContextMenu) => "Editor Context Menu"
    (SimplifiedChinese, EditorContextMenu) => "编辑器上下文菜单"
    (Japanese, EditorContextMenu) =>
      "エディターのコンテキストメニュー"
    (English, ShowContextMenu) => "Show Editor Context Menu"
    (SimplifiedChinese, ShowContextMenu) => "显示编辑器上下文菜单"
    (Japanese, ShowContextMenu) =>
      "エディターのコンテキストメニューを表示"
    (English, PeekLabel) => "Peek"
    (SimplifiedChinese, PeekLabel) => "速览"
    (Japanese, PeekLabel) => "ピーク"
    (English, GoDefinition) => "Go to Definition"
    (SimplifiedChinese, GoDefinition) => "转到定义"
    (Japanese, GoDefinition) => "定義へ移動"
    (English, PeekDefinition) => "Peek Definition"
    (SimplifiedChinese, PeekDefinition) => "速览定义"
    (Japanese, PeekDefinition) => "定義をピーク"
    (English, GoReferences) => "Go to References"
    (SimplifiedChinese, GoReferences) => "转到引用"
    (Japanese, GoReferences) => "参照へ移動"
    (English, PeekReferences) => "Peek References"
    (SimplifiedChinese, PeekReferences) => "速览引用"
    (Japanese, PeekReferences) => "参照をピーク"
    (English, NoDefinition) => "No definition found"
    (SimplifiedChinese, NoDefinition) => "未找到定义"
    (Japanese, NoDefinition) => "定義が見つかりません"
    (English, NoDefinitions) => "No definitions found"
    (SimplifiedChinese, NoDefinitions) => "未找到定义"
    (Japanese, NoDefinitions) => "定義が見つかりません"
    (English, NoReferences) => "No references found"
    (SimplifiedChinese, NoReferences) => "未找到引用"
    (Japanese, NoReferences) => "参照が見つかりません"
    (English, CannotOpenDefinition) => "Unable to open definition"
    (SimplifiedChinese, CannotOpenDefinition) => "无法打开定义"
    (Japanese, CannotOpenDefinition) => "定義を開けません"
    (English, CannotOpenReference) => "Unable to open reference"
    (SimplifiedChinese, CannotOpenReference) => "无法打开引用"
    (Japanese, CannotOpenReference) => "参照を開けません"
    (English, NoPreview) => "No preview available"
    (SimplifiedChinese, NoPreview) => "没有可用的预览"
    (Japanese, NoPreview) => "プレビューはありません"
    (English, OriginalSource) => "Original source"
    (SimplifiedChinese, OriginalSource) => "原始源码"
    (Japanese, OriginalSource) => "元のソース"
    (English, ShowSource) => "Show original source"
    (SimplifiedChinese, ShowSource) => "显示原始源码"
    (Japanese, ShowSource) => "元のソースを表示"
    (English, ShowDocumentation) => "Show rendered documentation"
    (SimplifiedChinese, ShowDocumentation) => "显示渲染后的文档"
    (Japanese, ShowDocumentation) =>
      "レンダリングされたドキュメントを表示"
    (English, CollapseDocumentation) => "Collapse API documentation"
    (SimplifiedChinese, CollapseDocumentation) => "折叠 API 文档"
    (Japanese, CollapseDocumentation) =>
      "API ドキュメントを折りたたむ"
    (English, ExpandDocumentation) => "Expand API documentation"
    (SimplifiedChinese, ExpandDocumentation) => "展开 API 文档"
    (Japanese, ExpandDocumentation) => "API ドキュメントを展開"
    (English, LoadingLabel) => "Loading..."
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (Japanese, LoadingLabel) => "読み込み中…"
    (English, LoadingPreview) => "Loading preview…"
    (SimplifiedChinese, LoadingPreview) => "正在加载预览…"
    (Japanese, LoadingPreview) => "プレビューを読み込み中…"
    (English, DefinitionsLabel) => "Definitions"
    (SimplifiedChinese, DefinitionsLabel) => "定义"
    (Japanese, DefinitionsLabel) => "定義"
    (English, ReferencesLabel) => "References"
    (SimplifiedChinese, ReferencesLabel) => "引用"
    (Japanese, ReferencesLabel) => "参照"
    (English, DefinitionPreview) => "Definition preview"
    (SimplifiedChinese, DefinitionPreview) => "定义预览"
    (Japanese, DefinitionPreview) => "定義のプレビュー"
    (English, ReferencePreview) => "Reference preview"
    (SimplifiedChinese, ReferencePreview) => "引用预览"
    (Japanese, ReferencePreview) => "参照のプレビュー"
    (English, LoadingDefinitions) => "Loading definitions…"
    (SimplifiedChinese, LoadingDefinitions) => "正在加载定义…"
    (Japanese, LoadingDefinitions) => "定義を読み込み中…"
    (English, LoadingReferences) => "Loading references…"
    (SimplifiedChinese, LoadingReferences) => "正在加载引用…"
    (Japanese, LoadingReferences) => "参照を読み込み中…"
    (English, CopyLabel) => "Copy"
    (SimplifiedChinese, CopyLabel) => "复制"
    (Japanese, CopyLabel) => "コピー"
    (English, NoResults) => "No results found"
    (SimplifiedChinese, NoResults) => "未找到结果"
    (Japanese, NoResults) => "結果が見つかりません"
    (English, AddFeedback) => "Add feedback"
    (SimplifiedChinese, AddFeedback) => "添加反馈"
    (Japanese, AddFeedback) => "フィードバックを追加"
    (English, FeedbackLabel) => "Feedback"
    (SimplifiedChinese, FeedbackLabel) => "反馈"
    (Japanese, FeedbackLabel) => "フィードバック"
    (English, CancelFeedback) => "Cancel feedback (Escape)"
    (SimplifiedChinese, CancelFeedback) => "取消反馈（Escape）"
    (Japanese, CancelFeedback) =>
      "フィードバックをキャンセル（Escape）"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, AddFeedbackBatch) => "Add feedback to the batch (Enter)"
    (SimplifiedChinese, AddFeedbackBatch) => "将反馈加入批次（Enter）"
    (Japanese, AddFeedbackBatch) =>
      "フィードバックをまとめて追加（Enter）"
    (English, ApplyFeedbackShortcut) => "Apply all feedback (Alt+Enter)"
    (SimplifiedChinese, ApplyFeedbackShortcut) =>
      "应用所有反馈（Alt+Enter）"
    (Japanese, ApplyFeedbackShortcut) =>
      "すべてのフィードバックを適用（Alt+Enter）"
    (English, ApplyFeedback) => "Apply all feedback"
    (SimplifiedChinese, ApplyFeedback) => "应用所有反馈"
    (Japanese, ApplyFeedback) => "すべてのフィードバックを適用"
    (English, CollapseLabel) => "Collapse"
    (SimplifiedChinese, CollapseLabel) => "折叠"
    (Japanese, CollapseLabel) => "折りたたむ"
    (English, ExpandLabel) => "Expand"
    (SimplifiedChinese, ExpandLabel) => "展开"
    (Japanese, ExpandLabel) => "展開"
    (English, AgentReview) => "Agent Review"
    (SimplifiedChinese, AgentReview) => "智能体审阅"
    (Japanese, AgentReview) => "エージェントレビュー"
    (English, AddToComment) => "Add to Comment"
    (SimplifiedChinese, AddToComment) => "添加到评论"
    (Japanese, AddToComment) => "コメントに追加"
    (English, EditLabel) => "Edit"
    (SimplifiedChinese, EditLabel) => "编辑"
    (Japanese, EditLabel) => "編集"
    (English, RemoveLabel) => "Remove"
    (SimplifiedChinese, RemoveLabel) => "移除"
    (Japanese, RemoveLabel) => "削除"
    (English, ShareComment) => "Share comment with agent"
    (SimplifiedChinese, ShareComment) => "与智能体分享评论"
    (Japanese, ShareComment) => "コメントをエージェントと共有"
    (English, AcceptLabel) => "Accept"
    (SimplifiedChinese, AcceptLabel) => "接受"
    (Japanese, AcceptLabel) => "承認"
    (English, RemoveComment) => "Remove agent comment"
    (SimplifiedChinese, RemoveComment) => "移除智能体评论"
    (Japanese, RemoveComment) => "エージェントのコメントを削除"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (Japanese, DeleteLabel) => "削除"
    (English, AddComment) => "Add a comment…"
    (SimplifiedChinese, AddComment) => "添加评论…"
    (Japanese, AddComment) => "コメントを追加…"
  }
}
