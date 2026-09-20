///|
/// A compact label for one recorded job event, not the job's current state.
/// No lookup of later events or Jobs panel data participates in formatting.
priv struct JobCaption {
  target : String
  status : String
}

///|
fn JobCaption::output(text : String) -> JobCaption? {
  guard text.strip_prefix("job ") is Some(rest) &&
    rest.split_once(" (") is Some((id, rest)) &&
    !id.is_blank() &&
    rest.split_once("): ") is Some((status, target)) &&
    !target.is_blank() &&
    JobCaption::known_status(status.to_owned()) else {
    return None
  }
  Some({ target: target.to_owned(), status: status.to_owned(), })
}

///|
fn JobCaption::notice(text : String) -> JobCaption? {
  guard text.strip_prefix("background job ") is Some(rest) &&
    rest.split_once(" finished (") is Some((id, rest)) &&
    !id.is_blank() &&
    rest.split_once("): ") is Some((status, label)) &&
    status != "running" &&
    JobCaption::known_status(status.to_owned()) else {
    return None
  }
  // The engine's notice wraps `description · command` in backticks and adds
  // output-reading instructions. Keep the original text in the row's title
  // and detailed mode; only this minimal caption omits the repeated command.
  let target = if label.strip_prefix("`") is Some(rest) {
    guard rest.rev_split_once("` — read its output with job_output (")
      is Some((label, _)) else {
      return None
    }
    label.split_once(" · ").map_or(label.to_owned(), pair => pair.0.to_owned())
  } else {
    label.to_owned()
  }
  guard !target.is_blank() else { return None }
  Some({ target, status: status.to_owned(), })
}

///|
fn JobCaption::known_status(status : String) -> Bool {
  status == "running" ||
  status == "stopped" ||
  status =~ re"^exit=-?[0-9]+$" ||
  status.has_prefix("stopped killed_at_") ||
  status.has_prefix("cleanup failed: ") ||
  status.has_prefix("output capture failed: ") ||
  status.has_prefix("killed: ")
}

///|
fn JobCaption::label(
  self : JobCaption,
  locale : @i18n.Locale,
  notice~ : Bool,
) -> String {
  let caption = if !notice {
    match locale {
      English => "Read output of job \"\{self.target}\""
      SimplifiedChinese => "读取任务“\{self.target}”的输出"
      TraditionalChinese => "讀取工作「\{self.target}」的輸出"
      Japanese => "ジョブ「\{self.target}」の出力を確認"
    }
  } else if self.status == "exit=0" {
    match locale {
      English => "Job \"\{self.target}\" completed"
      SimplifiedChinese => "任务“\{self.target}”已完成"
      TraditionalChinese => "工作「\{self.target}」已完成"
      Japanese => "ジョブ「\{self.target}」が完了"
    }
  } else if self.status == "stopped" {
    match locale {
      English => "Job \"\{self.target}\" stopped"
      SimplifiedChinese => "任务“\{self.target}”已停止"
      TraditionalChinese => "工作「\{self.target}」已停止"
      Japanese => "ジョブ「\{self.target}」が停止"
    }
  } else {
    match locale {
      English => "Job \"\{self.target}\" failed"
      SimplifiedChinese => "任务“\{self.target}”失败"
      TraditionalChinese => "工作「\{self.target}」失敗"
      Japanese => "ジョブ「\{self.target}」が失敗"
    }
  }
  if notice && (self.status == "exit=0" || self.status == "stopped") {
    return caption
  }
  let status = if self.status == "running" {
    // A historical read says nothing about whether the job is running now.
    match locale {
      English => "running when read"
      SimplifiedChinese => "读取时仍在运行"
      TraditionalChinese => "讀取時仍在執行"
      Japanese => "確認時は実行中"
    }
  } else if self.status.strip_prefix("exit=") is Some(code) {
    "exit \{code}"
  } else {
    self.status
  }
  "\{caption} (\{status})"
}
