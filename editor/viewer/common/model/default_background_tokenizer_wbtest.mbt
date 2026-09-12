///| Deterministic branch matrix for the default idle/deadline worker.

///|
priv struct WorkerIdleTask {
  callback : (TokenizationIdleDeadline) -> Unit
  active : Ref[Bool]
}

///|
priv struct WorkerZeroTask {
  callback : () -> Unit
  active : Ref[Bool]
}

///|
priv struct WorkerSchedulerHarness {
  scheduler : TokenizationScheduler
  idle : Array[WorkerIdleTask]
  zero : Array[WorkerZeroTask]
  now_values : Array[Double]
  before_next_now : Ref[(() -> Unit)?]
  trace : Array[String]
}

///|
fn worker_scheduler_harness() -> WorkerSchedulerHarness {
  let idle : Array[WorkerIdleTask] = []
  let zero : Array[WorkerZeroTask] = []
  let now_values : Array[Double] = []
  let mut now_index = 0
  let fallback_now = 0.0
  let before_next_now : Ref[(() -> Unit)?] = Ref(None)
  let trace : Array[String] = []
  let scheduler = TokenizationScheduler(
    idle=callback => {
      let active = Ref(true)
      trace.push("idle-scheduled")
      idle.push({ callback, active, })
      @base_common.Disposable::from(() => {
        trace.push("idle-cancelled")
        active.val = false
      })
    },
    zero_timeout=callback => {
      let active = Ref(true)
      trace.push("zero-scheduled")
      zero.push({ callback, active, })
      @base_common.Disposable::from(() => {
        trace.push("zero-cancelled")
        active.val = false
      })
    },
    delay=(_milliseconds, _callback) => @base_common.Disposable::from(() => ()),
    now=() => {
      match before_next_now.val {
        Some(callback) => {
          before_next_now.val = None
          callback()
        }
        None => ()
      }
      let value = if now_index < now_values.length() {
        let result = now_values[now_index]
        now_index += 1
        result
      } else {
        fallback_now
      }
      trace.push("now")
      value
    },
  )
  { scheduler, idle, zero, now_values, before_next_now, trace, }
}

///|
fn run_worker_idle(task : WorkerIdleTask, remaining : Double) -> Unit {
  if task.active.val {
    (task.callback)(TokenizationIdleDeadline(() => remaining))
  }
}

///|
fn run_worker_zero(task : WorkerZeroTask) -> Unit {
  if task.active.val {
    (task.callback)()
  }
}

///|
priv struct DefaultWorkerHarness {
  worker : DefaultBackgroundTokenizer
  attached : Ref[Int]
  lexer_calls : Array[String]
  token_batches : Ref[Int]
}

///|
fn default_worker_harness(
  line_count : Int,
  attached_count : Int,
  scheduling : WorkerSchedulerHarness,
) -> DefaultWorkerHarness raise {
  let lines : Array[String] = []
  for _ in 1..<=line_count {
    lines.push("line")
  }
  let attached = Ref(attached_count)
  let scheduler_value : Ref[TokenizationScheduler?] = Ref(
    Some(scheduling.scheduler),
  )
  let lexer_calls : Array[String] = []
  let model_state = test_tokenization_model_state(
    lines,
    "default-worker-test",
    attached,
    false,
    Ref(false),
    scheduler_value,
    _message => (),
  )
  let support = InternalTokenizationSupportAdapter(
    initial_state=() => TokenizerState(),
    tokenize_encoded=(text, _has_eol, _state) => {
      lexer_calls.push(text)
      scheduling.trace.push("lex")
      {
        tokens: [0, tag_to_metadata(Plain)],
        end_state: @syntax.TokenizerState().push_mode(b'l'),
      }
    },
  )
  let tokenizer = TokenizerWithStateStoreAndTextModel(
    line_count, support, model_state, @services.language_id_codec,
  )
  let token_batches = Ref(0)
  let output = BackgroundTokenizationStore(set_tokens=_batches => {
    token_batches.val += 1
    scheduling.trace.push("tokens")
  })
  {
    worker: DefaultBackgroundTokenizer(tokenizer, output),
    attached,
    lexer_calls,
    token_batches,
  }
}

///|
fn mark_worker_valid(worker : DefaultBackgroundTokenizer) -> Unit {
  let line_count = worker.tokenizer_with_state_store.model_state.snapshot.val.line_count()
  for line_number in 1..<=line_count {
    worker.tokenizer_with_state_store.base.store.set_end_state(
      line_number,
      @syntax.TokenizerState().push_mode(b'v'),
    )
    |> ignore
  }
}

///|
test "begin background tokenization has independent scheduled attached invalid guards" {
  for scheduled in [false, true] {
    for attached in [false, true] {
      for invalid in [false, true] {
        let scheduling = worker_scheduler_harness()
        let harness = default_worker_harness(
          1,
          if attached {
            1
          } else {
            0
          },
          scheduling,
        )
        if !invalid {
          mark_worker_valid(harness.worker)
        }
        harness.worker.is_scheduled = scheduled
        harness.worker.begin_background_tokenization()
        let expected = !scheduled && attached && invalid
        assert_eq(scheduling.idle.length(), if expected { 1 } else { 0 })
        assert_eq(harness.lexer_calls.length(), 0)
      }
    }
  }
}

///|
test "deadline is read immediately and end time is now plus remaining" {
  for boundary in [14.999, 15.0, 15.001] {
    let scheduling = worker_scheduler_harness()
    scheduling.now_values.append([10.0, 10.0, 10.0, 12.0, boundary])
    let harness = default_worker_harness(2, 1, scheduling)
    let mut deadline_live = true
    let mut deadline_reads = 0
    scheduling.before_next_now.val = Some(() => deadline_live = false)
    let deadline = TokenizationIdleDeadline(() => {
      if !deadline_live {
        abort("deadline read after leaving its live interval")
      }
      deadline_reads += 1
      scheduling.trace.push("remaining")
      5.0
    })
    harness.worker.background_tokenize_with_deadline(
      deadline,
      harness.worker.generation.val,
    )
    assert_eq(deadline_reads, 1)
    assert_false(deadline_live)
    assert_eq(scheduling.trace[0], "remaining")
    assert_eq(harness.lexer_calls.length(), 1)
    if boundary < 15.0 {
      assert_eq(scheduling.zero.length(), 1)
      assert_eq(scheduling.idle.length(), 0)
    } else {
      assert_eq(scheduling.zero.length(), 0)
      assert_eq(scheduling.idle.length(), 1)
    }
  }
}

///|
test "idle callback runs the first slice synchronously before zero timeout" {
  let scheduling = worker_scheduler_harness()
  scheduling.now_values.append([0.0, 0.0, 0.0, 2.0, 0.0])
  let harness = default_worker_harness(3, 1, scheduling)
  harness.worker.handle_changes()
  assert_eq(scheduling.idle.length(), 1)
  run_worker_idle(scheduling.idle[0], 100.0)
  assert_eq(harness.lexer_calls.length(), 1)
  assert_eq(scheduling.zero.length(), 1)
  let mut lex_index = -1
  let mut zero_index = -1
  for index, entry in scheduling.trace {
    if entry == "lex" {
      lex_index = index
    }
    if entry == "zero-scheduled" {
      zero_index = index
    }
  }
  assert_true(lex_index >= 0)
  assert_true(zero_index > lex_index)
  run_worker_zero(scheduling.zero[0])
  assert_eq(harness.lexer_calls.length(), 3)
}

///|
test "one millisecond tokenizes but a value strictly greater than one breaks" {
  let at_boundary = worker_scheduler_harness()
  at_boundary.now_values.append([0.0, 1.0])
  let at_boundary_worker = default_worker_harness(1, 1, at_boundary)
  at_boundary_worker.worker.background_tokenize_for_at_least_1ms()
  assert_eq(at_boundary_worker.lexer_calls.length(), 1)
  assert_eq(at_boundary_worker.token_batches.val, 1)

  let after_boundary = worker_scheduler_harness()
  after_boundary.now_values.append([0.0, 1.001])
  let after_boundary_worker = default_worker_harness(1, 1, after_boundary)
  after_boundary_worker.worker.background_tokenize_for_at_least_1ms()
  assert_eq(after_boundary_worker.lexer_calls.length(), 0)
  assert_eq(after_boundary_worker.token_batches.val, 1)
}

///|
test "slice stops at final line and otherwise continues while invalid states remain" {
  let scheduling = worker_scheduler_harness()
  scheduling.now_values.append([0.0, 0.0, 0.0, 0.0])
  let harness = default_worker_harness(3, 1, scheduling)
  harness.worker.background_tokenize_for_at_least_1ms()
  assert_eq(harness.lexer_calls.length(), 3)
  assert_false(harness.worker.has_lines_to_tokenize())
  assert_eq(harness.token_batches.val, 1)
}

///|
test "cancelled zero callback from an old generation performs no work" {
  let scheduling = worker_scheduler_harness()
  scheduling.now_values.append([0.0, 0.0, 0.0, 2.0, 0.0])
  let harness = default_worker_harness(3, 1, scheduling)
  harness.worker.handle_changes()
  run_worker_idle(scheduling.idle[0], 100.0)
  assert_eq(harness.lexer_calls.length(), 1)
  assert_eq(scheduling.zero.length(), 1)
  let old_zero = scheduling.zero[0]

  harness.attached.val = 0
  harness.worker.handle_changes()
  assert_false(old_zero.active.val)
  harness.attached.val = 1
  harness.worker.handle_changes()
  assert_eq(scheduling.idle.length(), 2)
  assert_true(harness.worker.is_scheduled)

  // A hostile host may still invoke a cancelled callback. Generation guards
  // return before lexing and cannot clear the fresh idle scheduling gate.
  (old_zero.callback)()
  assert_eq(harness.lexer_calls.length(), 1)
  assert_true(harness.worker.is_scheduled)
  assert_eq(scheduling.idle.length(), 2)
}

///|
test "dispose cancels idle and makes a hostile late callback inert" {
  let scheduling = worker_scheduler_harness()
  let harness = default_worker_harness(2, 1, scheduling)
  harness.worker.handle_changes()
  let old_idle = scheduling.idle[0]
  harness.worker.dispose()
  assert_false(old_idle.active.val)
  (old_idle.callback)(TokenizationIdleDeadline(() => 100.0))
  assert_eq(harness.lexer_calls.length(), 0)
  assert_false(harness.worker.is_scheduled)
}
