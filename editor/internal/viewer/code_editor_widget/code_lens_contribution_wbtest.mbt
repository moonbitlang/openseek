///|
priv struct ContributionCodeLensProvider {
  lenses : Array[@language.CodeLens]
  calls : Ref[Int]
}

///|
impl @language.CodeLensProvider for ContributionCodeLensProvider with fn provide_code_lenses(
  self,
  _model,
  _token,
) {
  self.calls.val += 1
  self.lenses.copy()
}

///|
priv struct BlockingContributionCodeLensProvider {
  lenses : Array[@language.CodeLens]
  calls : Ref[Int]
  first_started : @async.Semaphore
  release_first : @async.Semaphore
}

///|
impl @language.CodeLensProvider for BlockingContributionCodeLensProvider with fn provide_code_lenses(
  self,
  _model,
  _token,
) {
  self.calls.val += 1
  if self.calls.val == 1 {
    self.first_started.release()
    self.release_first.acquire() catch {
      _ => return []
    }
  }
  self.lenses.copy()
}

///|
priv struct CodeLensTestTimeout {
  callback : () -> Unit
  delay_ms : Int
  mut active : Bool
}

///|
priv struct CodeLensTestHost {
  timeouts : Array[CodeLensTestTimeout]
  tasks : Array[async () -> Unit noraise]
}

///|
fn CodeLensTestHost::CodeLensTestHost() -> CodeLensTestHost {
  { timeouts: [], tasks: [], }
}

///|
fn CodeLensTestHost::schedule(
  self : CodeLensTestHost,
  callback : () -> Unit,
  delay_ms : Int,
) -> @base_common.Disposable {
  let timeout = { callback, delay_ms, active: true, }
  self.timeouts.push(timeout)
  @base_common.Disposable::from(() => timeout.active = false)
}

///|
fn CodeLensTestHost::launch(
  self : CodeLensTestHost,
  task : async () -> Unit noraise,
) -> Unit {
  self.tasks.push(task)
}

///|
fn CodeLensTestHost::active_timeout_count(self : CodeLensTestHost) -> Int {
  for timeout in self.timeouts; count = 0 {
    if timeout.active {
      continue count + 1
    }
  } nobreak {
    count
  }
}

///|
fn CodeLensTestHost::run_next_timeout(self : CodeLensTestHost) -> Unit raise {
  for timeout in self.timeouts {
    if timeout.active {
      assert_eq(timeout.delay_ms, 250)
      timeout.active = false
      (timeout.callback)()
      return
    }
  }
  fail("expected a pending CodeLens timeout")
}

///|
async fn CodeLensTestHost::run_next_task(
  self : CodeLensTestHost,
) -> Unit noraise {
  guard !self.tasks.is_empty() else { return }
  let task = self.tasks.remove(0)
  task()
}

///|
fn contribution_code_lens(line : Int, title : String) -> @language.CodeLens {
  {
    range: Range(line, 1, line, 1),
    id: Some(title),
    command: Some({ id: "test.\{title}", title, tooltip: None, arguments: [], }),
  }
}

///|
struct CodeLensContributionTestBackings {
  services : CodeEditorServices
  languages : @languages.Languages
}

///|
fn CodeLensContributionTestBackings::CodeLensContributionTestBackings() -> CodeLensContributionTestBackings {
  let languages = @languages.Languages()
  let log_service = @log.LogService()
  {
    services: CodeEditorServices(
      languages=languages.language_handle(log_service.log_handle()),
      log_service=log_service.log_handle(),
    ),
    languages,
  }
}

///|
async test "CodeLens contribution debounces dynamic registration and drops invalid provider ranges" {
  let backings = CodeLensContributionTestBackings()
  let viewer = CodeEditorWidget(services=backings.services)
  let host = CodeLensTestHost()
  viewer.set_code_lens_host_for_test(
    (callback, delay_ms) => host.schedule(callback, delay_ms),
    task => host.launch(task),
  )
  let model = test_model("first\nsecond\n", language_id="moonbit")
  viewer.set_model(Some(model))
  assert_eq(host.active_timeout_count(), 0)
  assert_eq(viewer.code_lens_item_count_for_test(), 0)

  let lenses = [
    contribution_code_lens(2, "valid"),
    contribution_code_lens(99, "invalid"),
  ]
  let calls = Ref(0)
  let registration = backings.languages.register_code_lens_provider(
    LanguageId("moonbit"),
    ContributionCodeLensProvider::{ lenses, calls, },
  )
  assert_eq(host.active_timeout_count(), 1)
  host.run_next_timeout()
  assert_eq(host.tasks.length(), 1)
  host.run_next_task()
  assert_eq(calls.val, 1)
  assert_eq(viewer.code_lens_item_count_for_test(), 1)

  registration.dispose()
  assert_eq(host.active_timeout_count(), 0)
  assert_eq(viewer.code_lens_item_count_for_test(), 0)
  viewer.dispose()
  backings.services.dispose()
  model.dispose()
}

///|
async test "CodeLens contribution fences model replacement and option-disable stale work" {
  let backings = CodeLensContributionTestBackings()
  let lenses = [contribution_code_lens(1, "live")]
  let calls = Ref(0)
  let changes : @base_common.Emitter[Unit] = @base_common.Emitter()
  let first_started = @async.Semaphore(1, initial_value=0)
  let release_first = @async.Semaphore(1, initial_value=0)
  let registration = backings.languages.register_code_lens_provider(
    LanguageId("moonbit"),
    BlockingContributionCodeLensProvider::{
      lenses,
      calls,
      first_started,
      release_first,
    },
    on_did_change=callback => changes.event(_ => callback()),
  )
  let viewer = CodeEditorWidget(services=backings.services)
  let host = CodeLensTestHost()
  viewer.set_code_lens_host_for_test(
    (callback, delay_ms) => host.schedule(callback, delay_ms),
    task => host.launch(task),
  )
  let first = test_model("old\n", language_id="moonbit")
  let replacement = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/replacement",
    ),
    "replacement",
    "moonbit",
    1,
    "",
    "new\n",
  )
  viewer.set_model(Some(first))
  host.run_next_timeout()
  assert_eq(host.tasks.length(), 1)

  @async.with_task_group() <| group => {
    let stale_request = group.spawn(() => host.run_next_task())
    first_started.acquire()
    viewer.set_model(Some(replacement))
    release_first.release()
    stale_request.wait()
  }
  assert_eq(host.active_timeout_count(), 1)
  assert_eq(calls.val, 1)
  assert_eq(viewer.code_lens_item_count_for_test(), 0)

  host.run_next_timeout()
  host.run_next_task()
  assert_eq(calls.val, 2)
  assert_eq(viewer.code_lens_item_count_for_test(), 1)

  lenses.push(contribution_code_lens(1, "second"))
  changes.fire(())
  viewer.update_options(viewer.get_options().with_theme("light"))
  assert_eq(host.active_timeout_count(), 1)
  host.run_next_timeout()
  host.run_next_task()
  assert_eq(calls.val, 3)
  assert_eq(viewer.code_lens_item_count_for_test(), 2)

  changes.fire(())
  assert_eq(host.active_timeout_count(), 1)
  viewer.update_options(viewer.get_options().with_code_lens(false))
  assert_eq(host.active_timeout_count(), 0)
  assert_eq(viewer.code_lens_item_count_for_test(), 0)
  changes.fire(())
  assert_eq(host.active_timeout_count(), 0)

  viewer.update_options(viewer.get_options().with_code_lens(true))
  assert_eq(host.active_timeout_count(), 1)
  host.run_next_timeout()
  assert_eq(host.tasks.length(), 1)
  viewer.dispose()
  host.run_next_task()
  assert_eq(calls.val, 3)

  registration.dispose()
  backings.services.dispose()
  first.dispose()
  replacement.dispose()
}
