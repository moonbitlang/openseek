// Feature-owned UI messages; both built-in languages are exhaustive.

///|
priv enum Message {
  IndexingFiles
  SearchingSymbols
  FileSearchFailed
  SymbolSearchFailed
  NoFiles
  NoSymbols
  SearchWorkspaceFiles
  SearchFiles
  Files
  SearchWorkspaceSymbols
  SearchSymbols
  Symbols
}

///|
fn Message::text(self : Message, locale : @i18n.Locale) -> String {
  match (locale, self) {
    (English, IndexingFiles) => "Indexing files…"
    (SimplifiedChinese, IndexingFiles) => "正在索引文件…"
    (English, SearchingSymbols) => "Searching symbols…"
    (SimplifiedChinese, SearchingSymbols) => "正在搜索符号…"
    (English, FileSearchFailed) => "File search failed"
    (SimplifiedChinese, FileSearchFailed) => "文件搜索失败"
    (English, SymbolSearchFailed) => "Symbol search failed"
    (SimplifiedChinese, SymbolSearchFailed) => "符号搜索失败"
    (English, NoFiles) => "No files found"
    (SimplifiedChinese, NoFiles) => "未找到文件"
    (English, NoSymbols) => "No symbols found"
    (SimplifiedChinese, NoSymbols) => "未找到符号"
    (English, SearchWorkspaceFiles) => "Search workspace files"
    (SimplifiedChinese, SearchWorkspaceFiles) => "搜索工作区文件"
    (English, SearchFiles) => "Search files"
    (SimplifiedChinese, SearchFiles) => "搜索文件"
    (English, Files) => "Files"
    (SimplifiedChinese, Files) => "文件"
    (English, SearchWorkspaceSymbols) => "Search workspace symbols"
    (SimplifiedChinese, SearchWorkspaceSymbols) => "搜索工作区符号"
    (English, SearchSymbols) => "Search symbols"
    (SimplifiedChinese, SearchSymbols) => "搜索符号"
    (English, Symbols) => "Symbols"
    (SimplifiedChinese, Symbols) => "符号"
  }
}
