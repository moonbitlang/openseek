///|
priv enum DynamicMessage {
  DOpenFolder(String)
  DMatches(String)
  DFolders(String)
  DOpenSegment(String)
  DOpenSegmentFolder(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DOpenFolder(p0)) => "Open folder \{p0}"
    (SimplifiedChinese, DOpenFolder(p0)) => "打开文件夹 \{p0}"
    (Japanese, DOpenFolder(p0)) => "フォルダー \{p0} を開く"
    (English, DMatches(p0)) => "\{p0} matches"
    (SimplifiedChinese, DMatches(p0)) => "\{p0} 个匹配项"
    (Japanese, DMatches(p0)) => "\{p0} 件の一致"
    (English, DFolders(p0)) => "\{p0} folders"
    (SimplifiedChinese, DFolders(p0)) => "\{p0} 个文件夹"
    (Japanese, DFolders(p0)) => "\{p0} フォルダー"
    (English, DOpenSegment(p0)) => "Open \{p0}"
    (SimplifiedChinese, DOpenSegment(p0)) => "打开 \{p0}"
    (Japanese, DOpenSegment(p0)) => "\{p0} を開く"
    (English, DOpenSegmentFolder(p0)) => "Open folder \{p0}"
    (SimplifiedChinese, DOpenSegmentFolder(p0)) => "打开文件夹 \{p0}"
    (Japanese, DOpenSegmentFolder(p0)) => "フォルダー \{p0} を開く"
  }
}
