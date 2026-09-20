///|
fn JobEvent::minimal_caption(self : JobEvent, locale : @i18n.Locale) -> String? {
  let job = match self {
    Backgrounded(_) => return None
    OutputRead(job) | Finished(job) => job
  }
  if job.status is Unrecognized(_) {
    return None
  }
  let caption = if self is OutputRead(_) {
    match locale {
      English => "Read output of job \"\{job.description}\""
      SimplifiedChinese => "读取任务“\{job.description}”的输出"
      TraditionalChinese => "讀取工作「\{job.description}」的輸出"
      Japanese => "ジョブ「\{job.description}」の出力を確認"
    }
  } else if job.status is Exited(0) {
    match locale {
      English => "Job \"\{job.description}\" completed"
      SimplifiedChinese => "任务“\{job.description}”已完成"
      TraditionalChinese => "工作「\{job.description}」已完成"
      Japanese => "ジョブ「\{job.description}」が完了"
    }
  } else if job.status is Stopped {
    match locale {
      English => "Job \"\{job.description}\" stopped"
      SimplifiedChinese => "任务“\{job.description}”已停止"
      TraditionalChinese => "工作「\{job.description}」已停止"
      Japanese => "ジョブ「\{job.description}」が停止"
    }
  } else {
    match locale {
      English => "Job \"\{job.description}\" failed"
      SimplifiedChinese => "任务“\{job.description}”失败"
      TraditionalChinese => "工作「\{job.description}」失敗"
      Japanese => "ジョブ「\{job.description}」が失敗"
    }
  }
  if self is Finished(_) && job.status is (Exited(0) | Stopped) {
    return Some(caption)
  }
  Some("\{caption} (\{job.status.label(locale)})")
}

///|
fn JobStatus::label(self : JobStatus, locale : @i18n.Locale) -> String {
  match self {
    // A historical read says nothing about whether the job is running now.
    Running =>
      match locale {
        English => "running when read"
        SimplifiedChinese => "读取时仍在运行"
        TraditionalChinese => "讀取時仍在執行"
        Japanese => "確認時は実行中"
      }
    Exited(code) => "exit \{code}"
    Stopped => "stopped"
    StoppedAtLimit(reason) => "stopped killed_at_\{reason}"
    CleanupFailed(reason) => "cleanup failed: \{reason}"
    OutputCaptureFailed(reason) => "output capture failed: \{reason}"
    Killed(reason) => "killed: \{reason}"
    Unrecognized(text) => text
  }
}

///|
fn JobEvent::icon(self : JobEvent) -> @html.Html {
  match self {
    Backgrounded(_) => @icons.icon_terminal()
    OutputRead(_) => @icons.icon_arrow_down()
    Finished(job) =>
      match job.status {
        Exited(0) => @icons.icon_check()
        Stopped => @icons.icon_debug_stop()
        _ => @icons.icon_error()
      }
  }
}
