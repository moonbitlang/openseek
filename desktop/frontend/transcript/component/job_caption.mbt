///|
/// Presentation of one recorded event. Unrecognized text stays verbatim.
priv struct JobCaption {
  label : String
  icon : @html.Html
}

///|
fn job_caption(
  text : String,
  locale : @i18n.Locale,
  notice~ : Bool,
) -> JobCaption? {
  let (prefix, separator) = if notice {
    ("background job ", " finished (")
  } else {
    ("job ", " (")
  }
  guard text.strip_prefix(prefix) is Some(rest) &&
    rest.split_once(separator) is Some((id, rest)) &&
    !id.is_blank() &&
    rest.split_once("): ") is Some((status, target)) else {
    return None
  }
  let status = status.to_owned()
  guard (status == "running" && !notice) ||
    status == "stopped" ||
    status =~ re"^exit=-?[0-9]+$" ||
    status.has_prefix("stopped killed_at_") ||
    status.has_prefix("cleanup failed: ") ||
    status.has_prefix("output capture failed: ") ||
    status.has_prefix("killed: ") else {
    return None
  }
  // Only notices include the command and instructions after the description.
  // The complete original record remains in the tooltip and Detailed mode.
  let target = if notice && target.strip_prefix("`") is Some(rest) {
    guard rest.rev_split_once("` — read its output with job_output (")
      is Some((label, _)) else {
      return None
    }
    label.split_once(" · ").map_or(label.to_owned(), pair => pair.0.to_owned())
  } else {
    target.to_owned()
  }
  guard !target.is_blank() else { return None }
  let label = match (locale, notice, status) {
    (English, false, _) => "Read output of job \"\{target}\""
    (Spanish, false, _) => "Leer la salida del trabajo \"\{target}\""
    (SimplifiedChinese, false, _) => "读取任务“\{target}”的输出"
    (TraditionalChinese, false, _) => "讀取工作「\{target}」的輸出"
    (Japanese, false, _) => "ジョブ「\{target}」の出力を確認"
    (English, true, "exit=0") => "Job \"\{target}\" completed"
    (Spanish, true, "exit=0") => "El trabajo \"\{target}\" finalizó"
    (SimplifiedChinese, true, "exit=0") => "任务“\{target}”已完成"
    (TraditionalChinese, true, "exit=0") => "工作「\{target}」已完成"
    (Japanese, true, "exit=0") => "ジョブ「\{target}」が完了"
    (English, true, "stopped") => "Job \"\{target}\" stopped"
    (Spanish, true, "stopped") => "El trabajo \"\{target}\" se detuvo"
    (SimplifiedChinese, true, "stopped") => "任务“\{target}”已停止"
    (TraditionalChinese, true, "stopped") => "工作「\{target}」已停止"
    (Japanese, true, "stopped") => "ジョブ「\{target}」が停止"
    (English, true, _) => "Job \"\{target}\" failed"
    (Spanish, true, _) => "El trabajo \"\{target}\" falló"
    (SimplifiedChinese, true, _) => "任务“\{target}”失败"
    (TraditionalChinese, true, _) => "工作「\{target}」失敗"
    (Japanese, true, _) => "ジョブ「\{target}」が失敗"
  }
  let detail = if status == "running" {
    // This describes the recorded read, not whether the job is running now.
    match locale {
      English => "running when read"
      Spanish => "en ejecución al leer"
      SimplifiedChinese => "读取时仍在运行"
      TraditionalChinese => "讀取時仍在執行"
      Japanese => "確認時は実行中"
    }
  } else if status.strip_prefix("exit=") is Some(code) {
    "exit \{code}"
  } else {
    status
  }
  let icon = if !notice {
    @icons.icon_arrow_down()
  } else if status == "exit=0" {
    @icons.icon_check()
  } else if status == "stopped" {
    @icons.icon_debug_stop()
  } else {
    @icons.icon_error()
  }
  Some({
    label: if notice && (status == "exit=0" || status == "stopped") {
      label
    } else {
      "\{label} (\{detail})"
    },
    icon,
  })
}
