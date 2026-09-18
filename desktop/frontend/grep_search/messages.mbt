// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  SearchLabel
  TextSearch
  CodeSearch
  TextLabel
  CodeLabel
  MatchCase
  WholeWord
  RegularExpression
  RepairingPattern
  FixPattern
  PatternRepair
  NoHistory
  PatternInstruction
  RepairInstruction
  SubmitRepair
  SubmitLabel
  ThinkingLabel
  ValidationPassed
  ValidationUnavailable
  ValidationFailed
  ValidationUnknown
  SuggestedPattern
  RequiresValidation
  UsePattern
  DiscardLabel
  InvalidRegex
  InvalidGlob
  UnreadableWorkspace
  RipgrepUnavailable
  InvalidPattern
  SemanticUnavailable
  NothingToSearch
  SearchFailed
  NoMatches
  TextSearchDescription
  CodeSearchDescription
  ResultsCleared
  SearchingLabel
  ResultLimit
  IncompleteResults
  IncludeFiles
  ExcludeFiles
  IncludeExample
  ExcludeExample
  PatternLabel
  ToggleDetails
  RefreshLabel
  ClearResults
  ClearLabel
  CollapseAll
  NoCheckout
  OpenCheckoutDescription
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, SearchLabel) => "Search"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (English, TextSearch) => "Text search"
    (SimplifiedChinese, TextSearch) => "文本搜索"
    (English, CodeSearch) => "Code search"
    (SimplifiedChinese, CodeSearch) => "代码搜索"
    (English, TextLabel) => "Text"
    (SimplifiedChinese, TextLabel) => "文本"
    (English, CodeLabel) => "Code"
    (SimplifiedChinese, CodeLabel) => "代码"
    (English, MatchCase) => "Match Case"
    (SimplifiedChinese, MatchCase) => "区分大小写"
    (English, WholeWord) => "Match Whole Word"
    (SimplifiedChinese, WholeWord) => "全字匹配"
    (English, RegularExpression) => "Use Regular Expression"
    (SimplifiedChinese, RegularExpression) => "使用正则表达式"
    (English, RepairingPattern) => "Pattern Repair in progress"
    (SimplifiedChinese, RepairingPattern) => "正在修复模式"
    (English, FixPattern) => "Fix Pattern"
    (SimplifiedChinese, FixPattern) => "修复模式"
    (English, PatternRepair) => "PATTERN REPAIR"
    (SimplifiedChinese, PatternRepair) => "模式修复"
    (English, NoHistory) => "One request, no history"
    (SimplifiedChinese, NoHistory) => "单次请求，不保留历史"
    (English, PatternInstruction) =>
      "What should this pattern match? e.g. allow labelled arguments"
    (SimplifiedChinese, PatternInstruction) =>
      "此模式应匹配什么？例如：允许标签参数"
    (English, RepairInstruction) => "Pattern repair instruction"
    (SimplifiedChinese, RepairInstruction) => "模式修复说明"
    (English, SubmitRepair) => "Submit pattern repair"
    (SimplifiedChinese, SubmitRepair) => "提交模式修复"
    (English, SubmitLabel) => "Submit"
    (SimplifiedChinese, SubmitLabel) => "提交"
    (English, ThinkingLabel) => "Thinking"
    (SimplifiedChinese, ThinkingLabel) => "思考中"
    (English, ValidationPassed) => "Validation passed"
    (SimplifiedChinese, ValidationPassed) => "验证通过"
    (English, ValidationUnavailable) => "Validation unavailable"
    (SimplifiedChinese, ValidationUnavailable) => "验证不可用"
    (English, ValidationFailed) => "Validation failed"
    (SimplifiedChinese, ValidationFailed) => "验证失败"
    (English, ValidationUnknown) => "Validation status unknown"
    (SimplifiedChinese, ValidationUnknown) => "验证状态未知"
    (English, SuggestedPattern) => "SUGGESTED PATTERN"
    (SimplifiedChinese, SuggestedPattern) => "建议的模式"
    (English, RequiresValidation) =>
      "This candidate cannot be applied until validation passes."
    (SimplifiedChinese, RequiresValidation) =>
      "通过验证后才能应用此候选模式。"
    (English, UsePattern) => "Use pattern"
    (SimplifiedChinese, UsePattern) => "使用此模式"
    (English, DiscardLabel) => "Discard"
    (SimplifiedChinese, DiscardLabel) => "放弃"
    (English, InvalidRegex) => "Invalid regular expression"
    (SimplifiedChinese, InvalidRegex) => "正则表达式无效"
    (English, InvalidGlob) => "Invalid file pattern"
    (SimplifiedChinese, InvalidGlob) => "文件匹配模式无效"
    (English, UnreadableWorkspace) => "Workspace is not readable"
    (SimplifiedChinese, UnreadableWorkspace) => "无法读取工作区"
    (English, RipgrepUnavailable) => "Bundled ripgrep is unavailable"
    (SimplifiedChinese, RipgrepUnavailable) => "内置 ripgrep 不可用"
    (English, InvalidPattern) => "Invalid code pattern"
    (SimplifiedChinese, InvalidPattern) => "代码模式无效"
    (English, SemanticUnavailable) => "Semantic search is unavailable"
    (SimplifiedChinese, SemanticUnavailable) => "语义搜索不可用"
    (English, NothingToSearch) => "Nothing to search"
    (SimplifiedChinese, NothingToSearch) => "没有可搜索的内容"
    (English, SearchFailed) => "Search failed"
    (SimplifiedChinese, SearchFailed) => "搜索失败"
    (English, NoMatches) => "No matches found."
    (SimplifiedChinese, NoMatches) => "未找到匹配项。"
    (English, TextSearchDescription) =>
      "Search across files in the current checkout."
    (SimplifiedChinese, TextSearchDescription) =>
      "在当前检出目录中跨文件搜索。"
    (English, CodeSearchDescription) =>
      "Search MoonBit code patterns in the current checkout."
    (SimplifiedChinese, CodeSearchDescription) =>
      "在当前检出目录中搜索 MoonBit 代码模式。"
    (English, ResultsCleared) =>
      "Search results cleared. Press Enter to search again."
    (SimplifiedChinese, ResultsCleared) =>
      "搜索结果已清空。按 Enter 重新搜索。"
    (English, SearchingLabel) => "Searching…"
    (SimplifiedChinese, SearchingLabel) => "正在搜索…"
    (English, ResultLimit) =>
      "Only the first 20,000 matches are shown. Narrow the search to see more."
    (SimplifiedChinese, ResultLimit) =>
      "仅显示前 20,000 个匹配项。请缩小搜索范围以查看更多结果。"
    (English, IncompleteResults) =>
      "Results may be incomplete — some files could not be searched."
    (SimplifiedChinese, IncompleteResults) =>
      "部分文件无法搜索，结果可能不完整。"
    (English, IncludeFiles) => "files to include"
    (SimplifiedChinese, IncludeFiles) => "包含的文件"
    (English, ExcludeFiles) => "files to exclude"
    (SimplifiedChinese, ExcludeFiles) => "排除的文件"
    (English, IncludeExample) => "e.g. src/**, *.mbt"
    (SimplifiedChinese, IncludeExample) => "例如 src/**, *.mbt"
    (English, ExcludeExample) => "e.g. **/*.snap, generated/**"
    (SimplifiedChinese, ExcludeExample) => "例如 **/*.snap, generated/**"
    (English, PatternLabel) => "pattern"
    (SimplifiedChinese, PatternLabel) => "模式"
    (English, ToggleDetails) => "Toggle Search Details"
    (SimplifiedChinese, ToggleDetails) => "展开或收起搜索详情"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (English, ClearResults) => "Clear Search Results"
    (SimplifiedChinese, ClearResults) => "清空搜索结果"
    (English, ClearLabel) => "Clear"
    (SimplifiedChinese, ClearLabel) => "清空"
    (English, CollapseAll) => "Collapse All"
    (SimplifiedChinese, CollapseAll) => "全部折叠"
    (English, NoCheckout) => "No checkout available"
    (SimplifiedChinese, NoCheckout) => "没有可用的检出目录"
    (English, OpenCheckoutDescription) =>
      "Open a conversation or task with a checkout to search its files."
    (SimplifiedChinese, OpenCheckoutDescription) =>
      "打开具有检出目录的对话或任务，即可搜索其中的文件。"
  }
}
