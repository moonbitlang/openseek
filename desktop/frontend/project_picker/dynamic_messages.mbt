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
    (English, DMatches(p0)) => "\{p0} matches"
    (SimplifiedChinese, DMatches(p0)) => "\{p0} 个匹配项"
    (English, DFolders(p0)) => "\{p0} folders"
    (SimplifiedChinese, DFolders(p0)) => "\{p0} 个文件夹"
    (English, DOpenSegment(p0)) => "Open \{p0}"
    (SimplifiedChinese, DOpenSegment(p0)) => "打开 \{p0}"
    (English, DOpenSegmentFolder(p0)) => "Open folder \{p0}"
    (SimplifiedChinese, DOpenSegmentFolder(p0)) => "打开文件夹 \{p0}"
  }
}
