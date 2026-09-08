///|
priv suberror CodeLensTestError {
  CodeLensTestError
}

///|
priv struct RecordingCodeLensProvider {
  lenses : Array[@language.CodeLens]
  calls : Ref[Int]
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
priv struct RecordingCodeLensResolver {
  calls : Ref[Int]
  title : String
}

///|
impl @language.CodeLensResolver for RecordingCodeLensResolver with fn resolve_code_lens(
  self,
  _model,
  lens,
  _token,
) {
  self.calls.val += 1
  Some({
    ..lens,
    command: Some({
      id: "test.resolve",
      title: self.title,
      tooltip: Some("resolved tooltip"),
      arguments: [Json("payload")],
    }),
  })
}

///|
fn test_code_lens(
  line : Int,
  column : Int,
  title? : String,
) -> @language.CodeLens {
  {
    range: Range(line, column, line, column),
    id: Some("\{line.to_string()}:\{column.to_string()}"),
    command: title.map(title => {
      id: "test.command",
      title,
      tooltip: None,
      arguments: [],
    }),
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
    items.map(item => item.lens().id.unwrap()).join("|"),
    "1:4|1:8|3:7|3:2|3:9",
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
async test "CodeLens resolver and change event retain the captured registration lifetime" {
  let languages = Languages()
  let model = test_model()
  let changes : @base_common.Emitter[Unit] = Emitter()
  let delivered = Ref(0)
  let handle = languages.language_handle(@log.LogService().log_handle())
  let listener = handle.on_did_change_code_lenses(() => delivered.val += 1)
  let resolver_calls = Ref(0)
  let registration = languages.register_code_lens_provider(
    LanguageId("moonbit"),
    RecordingCodeLensProvider::{
      lenses: [test_code_lens(2, 1)],
      calls: Ref(0),
      failing: false,
    },
    resolver=RecordingCodeLensResolver::{
      calls: resolver_calls,
      title: "resolved",
    },
    on_did_change=callback => changes.event(_ => callback()),
  )
  assert_eq(delivered.val, 1)
  changes.fire(())
  assert_eq(delivered.val, 2)
  let items = handle.code_lenses(model)
  assert_eq(items.length(), 1)
  assert_true(items[0].has_resolver())
  let resolved = handle.resolve_code_lens(model, items[0], items[0].lens())
  guard resolved is Some({ command: Some(command), .. }) else {
    fail("expected resolved CodeLens command")
  }
  assert_eq(command.title, "resolved")
  assert_eq(command.tooltip, Some("resolved tooltip"))
  assert_eq(command.arguments.length(), 1)
  assert_eq(resolver_calls.val, 1)
  registration.dispose()
  assert_eq(delivered.val, 3)
  changes.fire(())
  assert_eq(delivered.val, 3)
  assert_true(
    handle.resolve_code_lens(model, items[0], items[0].lens()) is None,
  )
  assert_eq(resolver_calls.val, 1)
  listener.dispose()
}
