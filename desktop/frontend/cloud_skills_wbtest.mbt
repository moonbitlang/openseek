///|
fn cloud_skills_test_account(token : String) -> @protocol.AccountSession {
  { token, user: { user_id: token, login: token, avatar_url: "", }, }
}

///|
fn cloud_skills_test_item(
  id : String,
  builtin~ : Bool,
) -> @skills.InstalledItem {
  {
    id,
    name: id,
    description: "",
    source: "acme/\{id}@1.0.0",
    registry: Some({ module_name: "acme/\{id}", package_path: "", }),
    enabled: true,
    builtin,
  }
}

///|
/// A browser page with no device, as browser Cloud is.
fn hostless_test_model() -> Model {
  let model = test_model()
  {
    ..model,
    is_desktop: false,
    devices: [],
    console: { ..model.console, page_device: None, },
  }
}

///|
test "the Skills page shows Cloud's library without a host and on request" {
  let account = cloud_skills_test_account("ts_A")
  let desktop = { ..test_model(), account: Some(account), }
  // A signed-in Desktop offers the switch and starts on the device.
  let input = desktop.skills_input()
  assert_true(input.library == Host(desktop.focused))
  assert_true(input.switchable)
  let chosen = { ..desktop, skills_library: CloudLibrary, }
  guard chosen.cloud_skills_access() is Some(access) else { fail("signed in") }
  assert_true(chosen.skills_input().library == Cloud(access))
  // Signed out, a chosen Cloud library is not available.
  let signed_out = { ..chosen, account: None, }
  assert_true(signed_out.skills_input().library == Host(signed_out.focused))
  assert_false(signed_out.skills_input().switchable)
  // A browser page without a host has only the Cloud library.
  let browser = { ..hostless_test_model(), account: Some(account), }
  assert_true(browser.skills_input().library is Cloud(_))
  assert_false(browser.skills_input().switchable)
}

///|
test "the switch selects the Cloud library and reads it" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    account: Some(cloud_skills_test_account("ts_A")),
    management_dialog: Some(Skills),
  }
  let (_, switched) = update(
    dispatch,
    Skills(@skills.SelectLibrary(CloudLibrary)),
    model,
  )
  assert_true(switched.skills_library is CloudLibrary)
  assert_true(switched.skills_input().library is Cloud(_))
  // Selecting the shown library again changes nothing.
  let (_, again) = update(
    dispatch,
    Skills(@skills.SelectLibrary(CloudLibrary)),
    switched,
  )
  assert_true(again.skills_library is CloudLibrary)
  assert_true(again.skills == switched.skills)
}

///|
test "Cloud library reads apply only to the account that issued them" {
  let dispatch = test_dispatch()
  let model = {
    ..hostless_test_model(),
    account: Some(cloud_skills_test_account("ts_A")),
  }
  guard model.cloud_skills_access() is Some(access) else { fail("signed in") }
  let items = [
    cloud_skills_test_item("typst", builtin=true),
    cloud_skills_test_item("alpha", builtin=false),
  ]
  let (_, loaded) = update(
    dispatch,
    CloudSkillsLoaded(access, Ok(items)),
    model,
  )
  assert_eq(loaded.cloud_skills.map(item => item.id), ["typst", "alpha"])
  assert_eq(loaded.skills_input().installed.length(), 2)
  // A read issued with another token is dropped.
  let (_, stale) = update(
    dispatch,
    CloudSkillsLoaded({ ..access, token: "ts_old", }, Ok([])),
    loaded,
  )
  assert_eq(stale.cloud_skills.length(), 2)
  // A failure for the shown library becomes the page's notice.
  let (_, failed) = update(
    dispatch,
    CloudSkillsLoaded(access, Err("Cloud is unreachable.")),
    loaded,
  )
  assert_eq(failed.cloud_skills.length(), 2)
  assert_true(
    failed.skills == loaded.skills.with_library_error("Cloud is unreachable."),
  )
}

///|
test "an account change drops the previous account's Cloud skills" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    account: Some(cloud_skills_test_account("ts_A")),
    cloud_skills: [cloud_skills_test_item("alpha", builtin=false)],
  }
  let (_, changed) = update(
    dispatch,
    AccountLoaded(
      model.account_epoch,
      Ok(Some(cloud_skills_test_account("ts_B"))),
    ),
    model,
  )
  assert_eq(changed.cloud_skills.length(), 0)
  let (_, same) = update(
    dispatch,
    AccountLoaded(model.account_epoch, Ok(model.account)),
    model,
  )
  assert_eq(same.cloud_skills.length(), 1)
}
