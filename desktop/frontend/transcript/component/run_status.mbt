///|
fn run_clock(input : @rabbita.Val[Input]) -> @rabbita.Val[Double] {
  // Input changes do not reinstall subscriptions on an existing component.
  // Mount the clock only while there is a known start time to measure from.
  input
  .map(input => input.run.bind(run => run.started_ms) is Some(_))
  .switch_by(by=ticking => if ticking { "running" } else { "idle" }, ticking => {
    if !ticking {
      return @rabbita.Val::constant(0.0)
    }
    let (clock, _) = @rabbita.create_state(
      @interop.now_ms(),
      update=(_, _ : Unit, _) => (@interop.now_ms(), @cmd.none),
      subscriptions=(_, emit) => @sub.every(1000, emit(())),
    )
    clock
  })
}

///|
fn run_status_row(
  locale : @i18n.Locale,
  run : @transcript.RunHeartbeat,
  clock_ms : Double,
) -> @html.Html {
  let dots = match run.stage {
    Thinking | Compacting | Retrying(..) => "transcript-run-dots swapping"
    AwaitingApproval | AwaitingAnswer => "transcript-run-dots paused"
    Starting | Working | Stopping => "transcript-run-dots"
  }
  @html.div(
    class=if run.stage is Retrying(..) {
      "transcript-run-status retrying"
    } else {
      "transcript-run-status"
    },
    [
      @html.span(
        class=dots,
        attrs=@html.Attrs::build().aria_hidden("true"),
        Array::makei(4, _ => @html.span("")),
      ),
      @html.span(run_status_label(locale, run, clock_ms)),
    ],
  )
}

///|
fn run_status_label(
  locale : @i18n.Locale,
  run : @transcript.RunHeartbeat,
  clock_ms : Double,
) -> String {
  let step = run.step.map(step => run_step_label(locale, step))
  let (stage, step) = if run.stage is Working {
    (working_label(locale, step), None)
  } else {
    (run_stage_label(locale, run.stage), step)
  }
  let detail : Array[String] = []
  if step is Some(step) {
    detail.push(step)
  }
  if run.started_ms is Some(started) && clock_ms > started {
    detail.push(@labels.duration(clock_ms - started))
  }
  if run.tokens > 0 {
    let tokens = @labels.compact_count(run.tokens)
    detail.push(
      match locale {
        English | Spanish => "\{tokens} tokens"
        SimplifiedChinese => "\{tokens} 个词元"
        TraditionalChinese => "\{tokens} 個詞元"
        Japanese => "\{tokens} トークン"
      },
    )
  }
  if detail.is_empty() {
    stage
  } else {
    "\{stage} (\{detail.join(" · ")})"
  }
}

///|
fn run_step_label(locale : @i18n.Locale, step : Int32) -> String {
  match locale {
    English => "step \{step}"
    Spanish => "paso \{step}"
    SimplifiedChinese | TraditionalChinese => "第 \{step} 步"
    Japanese => "ステップ \{step}"
  }
}

///|
fn working_label(locale : @i18n.Locale, step : String?) -> String {
  let working = match locale {
    English => "Working"
    Spanish => "Trabajando"
    SimplifiedChinese => "正在处理"
    TraditionalChinese => "正在處理"
    Japanese => "処理中"
  }
  match step {
    Some(step) => "\{working} · \{step}"
    None => "\{working}…"
  }
}

///|
fn run_stage_label(
  locale : @i18n.Locale,
  stage : @transcript.RunStage,
) -> String {
  match (locale, stage) {
    (_, Thinking) => ui(locale, ThinkingLabel)
    (English, Starting) => "Starting…"
    (Spanish, Starting) => "Iniciando…"
    (SimplifiedChinese, Starting) => "正在启动…"
    (TraditionalChinese, Starting) => "正在啟動…"
    (Japanese, Starting) => "起動中…"
    (English, Compacting) => "Compacting context…"
    (Spanish, Compacting) => "Compactando el contexto…"
    (SimplifiedChinese, Compacting) => "正在压缩上下文…"
    (TraditionalChinese, Compacting) => "正在壓縮上下文…"
    (Japanese, Compacting) => "コンテキストを圧縮中…"
    (English, AwaitingApproval) => "Waiting for your approval…"
    (Spanish, AwaitingApproval) => "Esperando tu aprobación…"
    (SimplifiedChinese, AwaitingApproval) => "等待你审批…"
    (TraditionalChinese, AwaitingApproval) => "等待你審批…"
    (Japanese, AwaitingApproval) => "承認を待っています…"
    (English, AwaitingAnswer) => "Waiting for your answer…"
    (Spanish, AwaitingAnswer) => "Esperando tu respuesta…"
    (SimplifiedChinese, AwaitingAnswer) => "等待你回答…"
    (TraditionalChinese, AwaitingAnswer) => "等待你回答…"
    (Japanese, AwaitingAnswer) => "回答を待っています…"
    (English, Retrying(attempt~, max_attempts~, reason~)) =>
      "Retrying · attempt \{attempt}/\{max_attempts} · \{reason}"
    (Spanish, Retrying(attempt~, max_attempts~, reason~)) =>
      "Reintentando · intento \{attempt}/\{max_attempts} · \{reason}"
    (SimplifiedChinese, Retrying(attempt~, max_attempts~, reason~)) =>
      "正在重试 · 第 \{attempt}/\{max_attempts} 次 · \{reason}"
    (TraditionalChinese, Retrying(attempt~, max_attempts~, reason~)) =>
      "正在重試 · 第 \{attempt}/\{max_attempts} 次 · \{reason}"
    (Japanese, Retrying(attempt~, max_attempts~, reason~)) =>
      "再試行中 · \{attempt}/\{max_attempts} 回 · \{reason}"
    (_, Working) => working_label(locale, None)
    (English, Stopping) => "Stopping…"
    (Spanish, Stopping) => "Deteniendo…"
    (SimplifiedChinese, Stopping) => "正在停止…"
    (TraditionalChinese, Stopping) => "正在停止…"
    (Japanese, Stopping) => "停止中…"
  }
}
