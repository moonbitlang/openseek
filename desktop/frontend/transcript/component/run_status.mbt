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
  @html.div(
    class=if run.stage is Retrying(..) {
      "transcript-run-status retrying"
    } else {
      "transcript-run-status"
    },
    [
      @html.span(class="transcript-run-mark", ""),
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
  let stage = run_stage_label(locale, run.stage)
  let detail : Array[String] = []
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
    (English, AtStep(step)) => "Working · step \{step}"
    (Spanish, AtStep(step)) => "Trabajando · paso \{step}"
    (SimplifiedChinese, AtStep(step)) => "正在处理 · 第 \{step} 步"
    (TraditionalChinese, AtStep(step)) => "正在處理 · 第 \{step} 步"
    (Japanese, AtStep(step)) => "処理中 · ステップ \{step}"
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
    (English, Working) => "Working…"
    (Spanish, Working) => "Trabajando…"
    (SimplifiedChinese, Working) => "正在处理…"
    (TraditionalChinese, Working) => "正在處理…"
    (Japanese, Working) => "処理中…"
    (English, Stopping) => "Stopping…"
    (Spanish, Stopping) => "Deteniendo…"
    (SimplifiedChinese, Stopping) => "正在停止…"
    (TraditionalChinese, Stopping) => "正在停止…"
    (Japanese, Stopping) => "停止中…"
  }
}
