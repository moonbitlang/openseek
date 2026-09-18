///|
priv enum DynamicMessage {
  DFailedExit(String)
  DStopped(String)
  DEnded(String, String)
  DRunningTime(String)
  DHost(String, String)
  DStarted(String)
  DWorkingDirectory(String)
  DLastOutput(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DFailedExit(p0)) => "Failed · exit \{p0}"
    (SimplifiedChinese, DFailedExit(p0)) => "失败 · 退出码 \{p0}"
    (English, DStopped(p0)) => "Stopped · \{p0}"
    (SimplifiedChinese, DStopped(p0)) => "已停止 · \{p0}"
    (English, DEnded(p0, p1)) => "Ended \{p0} · Total \{p1}s"
    (SimplifiedChinese, DEnded(p0, p1)) => "结束于 \{p0} · 共 \{p1} 秒"
    (English, DRunningTime(p0)) => "Running for \{p0}s"
    (SimplifiedChinese, DRunningTime(p0)) => "已运行 \{p0} 秒"
    (English, DHost(p0, p1)) => "Host: \{p0} · \{p1}"
    (SimplifiedChinese, DHost(p0, p1)) => "主机：\{p0} · \{p1}"
    (English, DStarted(p0)) => "Started \{p0}"
    (SimplifiedChinese, DStarted(p0)) => "开始于 \{p0}"
    (English, DWorkingDirectory(p0)) => "Working directory: \{p0}"
    (SimplifiedChinese, DWorkingDirectory(p0)) => "工作目录：\{p0}"
    (English, DLastOutput(p0)) => "Last output \{p0}s ago"
    (SimplifiedChinese, DLastOutput(p0)) => "上次输出在 \{p0} 秒前"
  }
}
