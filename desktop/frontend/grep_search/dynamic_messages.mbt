///|
priv enum DynamicMessage {
  DOpenMatch(String, String)
  DRepairDiagnostic(String)
  DMoreResults(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DOpenMatch(p0, p1)) => "Open \{p0}:\{p1}"
    (SimplifiedChinese, DOpenMatch(p0, p1)) => "打开 \{p0}:\{p1}"
    (English, DRepairDiagnostic(p0)) =>
      "The current pattern is invalid. Fix it using this diagnostic: \{p0}"
    (SimplifiedChinese, DRepairDiagnostic(p0)) =>
      "当前模式无效，请根据此诊断修复：\{p0}"
    (English, DMoreResults(p0)) => "Show \{p0} more results"
    (SimplifiedChinese, DMoreResults(p0)) => "再显示 \{p0} 个结果"
  }
}
