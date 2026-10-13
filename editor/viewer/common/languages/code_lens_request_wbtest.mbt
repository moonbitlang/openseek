///|
priv suberror CodeLensTestError {
  CodeLensTestError
}

///|
priv struct RecordingCodeLensProvider {
  lenses : Array[@language.CodeLens]
  calls : Ref[Int32]
  failing : Bool
}

///|
impl @language.CodeLensProvider for RecordingCodeLensProvider with fn provide_code_lenses(
  self,
  _model,
  _token,
) {
  self.calls.val += 1
  if self.failing {
    raise CodeLensTestError
  }
  self.lenses.copy()
}

///|
fn test_code_lens(
  line : Int32,
  column : Int32,
  title? : String,
) -> @language.CodeLens {
  {
    range: Range(line, column, line, column),
    title: title.unwrap_or("reference"),
    tooltip: None,
    execute: () => (),
  }
}

///|
async test "CodeLens query isolates failures and sorts independently of completion order" {
  let memory = @log.MemoryLogger()
  let languages = Languages()
  let model = test_model()
  let wildcard_calls = Ref(0)
  languages.register_code_lens_provider(LanguageId("*"), RecordingCodeLensProvider::{
    lenses: [test_code_lens(1, 8, title="wildcard")],
    calls: wildcard_calls,
    failing: false,
  })
  |> ignore
  let older_calls = Ref(0)
  languages.register_code_lens_provider(LanguageId("moonbit"), RecordingCodeLensProvider::{
    lenses: [
      test_code_lens(3, 9, title="older-column-9"),
      test_code_lens(1, 4, title="older-line-1"),
      test_code_lens(3, 2, title="older-column-2"),
    ],
    calls: older_calls,
    failing: false,
  })
  |> ignore
  let failing_calls = Ref(0)
  languages.register_code_lens_provider(LanguageId("moonbit"), RecordingCodeLensProvider::{
    lenses: [],
    calls: failing_calls,
    failing: true,
  })
  |> ignore
  let newer_calls = Ref(0)
  languages.register_code_lens_provider(LanguageId("moonbit"), RecordingCodeLensProvider::{
    lenses: [test_code_lens(3, 7, title="newer")],
    calls: newer_calls,
    failing: false,
  })
  |> ignore
  let handle = languages.language_handle(
    @log.LogService(logger=memory).log_handle(),
  )
  let items = handle.code_lenses(model, run_tasks=async fn(tasks) {
    for index = tasks.length() - 1; index >= 0; index = index - 1 {
      tasks[index]()
    }
  })
  assert_eq(items.length(), 5)
  assert_eq(
    items.map(item => item.title).join("|"),
    "older-line-1|wildcard|newer|older-column-9|older-column-2",
  )
  assert_eq(wildcard_calls.val, 1)
  assert_eq(older_calls.val, 1)
  assert_eq(failing_calls.val, 1)
  assert_eq(newer_calls.val, 1)
  let entries = memory.entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].category, "language.codeLens")
}

///|
async test "CodeLens query rejects cancelled and disposed registrations" {
  let languages = Languages()
  let model = test_model()
  let calls = Ref(0)
  let registration = languages.register_code_lens_provider(
    LanguageId("moonbit"),
    RecordingCodeLensProvider::{
      lenses: [test_code_lens(1, 1, title="live")],
      calls,
      failing: false,
    },
  )
  let handle = languages.language_handle(@log.LogService().log_handle())
  let cancelled = @language.CancellationToken::cancelled()
  assert_true(handle.code_lenses(model, token=cancelled).is_empty())
  assert_eq(calls.val, 0)
  let disposed_result = handle.code_lenses(model, run_tasks=async fn(tasks) {
    registration.dispose()
    for task in tasks {
      task()
    }
  })
  assert_true(disposed_result.is_empty())
  assert_eq(calls.val, 0)
  assert_false(handle.has_code_lens_provider(model))
}

///|
test "CodeLens invalidation subscription ends with provider registration" {
  let languages = Languages()
  let changes : @base_common.Emitter[Unit] = Emitter()
  let delivered = Ref(0)
  let handle = languages.language_handle(@log.LogService().log_handle())
  let listener = handle.on_did_change_code_lenses(() => delivered.val += 1)
  let registration = languages.register_code_lens_provider(
    LanguageId("moonbit"),
    RecordingCodeLensProvider::{ lenses: [], calls: Ref(0), failing: false, },
    on_did_change=callback => changes.event(_ => callback()),
  )
  assert_eq(delivered.val, 1)
  changes.fire(())
  assert_eq(delivered.val, 2)
  registration.dispose()
  assert_eq(delivered.val, 3)
  changes.fire(())
  assert_eq(delivered.val, 3)
  listener.dispose()
}
