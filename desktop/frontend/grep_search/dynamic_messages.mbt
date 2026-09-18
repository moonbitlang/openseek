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
    (TraditionalChinese, DOpenMatch(p0, p1)) => "開啟 \{p0}:\{p1}"
    (Japanese, DOpenMatch(p0, p1)) => "\{p0}:\{p1} を開く"
    (English, DRepairDiagnostic(p0)) =>
      "The current pattern is invalid. Fix it using this diagnostic: \{p0}"
    (SimplifiedChinese, DRepairDiagnostic(p0)) =>
      "当前模式无效，请根据此诊断修复：\{p0}"
    (TraditionalChinese, DRepairDiagnostic(p0)) =>
      "當前模式無效，請根據此診斷修復：\{p0}"
    (Japanese, DRepairDiagnostic(p0)) =>
      "現在のパターンは無効です。次の診断に基づいて修正してください：\{p0}"
    (English, DMoreResults(p0)) => "Show \{p0} more results"
    (SimplifiedChinese, DMoreResults(p0)) => "再显示 \{p0} 个结果"
    (TraditionalChinese, DMoreResults(p0)) => "再顯示 \{p0} 個結果"
    (Japanese, DMoreResults(p0)) => "さらに \{p0} 件を表示"
  }
}
