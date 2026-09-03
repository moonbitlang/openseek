// Real-Chromium CodeLens fixture. Provider lifecycle and stale-result fencing
// stay in MoonBit white-box tests; this scenario owns DOM geometry, native
// input, lazy visible resolution, CSS, and viewport preservation.

///|
fn browser_code_lens_source() -> String {
  let source = StringBuilder()
  for line in 1..<=60 {
    if line > 1 {
      source.write_char('\n')
    }
    match line {
      2 => source.write_string("    fn first_target() {}")
      10 => source.write_string("  fn expanded_ten() {}")
      20 => source.write_string("      fn expanded_twenty() {}")
      40 => source.write_string("        fn late_target() {}")
      _ => source <+ "padding_line_\{line}"
    }
  }
  source.to_string()
}

///|
fn browser_code_lens_command(
  id : String,
  title : String,
  tooltip? : String,
) -> @language.CodeLensCommand {
  {
    id,
    title,
    tooltip,
    arguments: [Json("payload"), Json(7), Json({ "nested": true })],
  }
}

///|
fn browser_code_lens(
  line : Int,
  column : Int,
  id : String,
  command? : @language.CodeLensCommand,
) -> @language.CodeLens {
  { range: Range(line, column, line, column), id: Some(id), command, }
}

///|
priv struct BrowserCodeLensProvider {
  mode : Ref[Int]
  calls : Ref[Int]
}

///|
impl @language.CodeLensProvider for BrowserCodeLensProvider with fn provide_code_lenses(
  self,
  _model,
  _token,
) {
  self.calls.val += 1
  let result = [
    browser_code_lens(
      2,
      5,
      "eager-2",
      command=browser_code_lens_command(
        "fixture.references",
        "3 references",
        tooltip="Show all references",
      ),
    ),
    browser_code_lens(2, 6, "resolve-2"),
    browser_code_lens(40, 9, "resolve-40"),
    browser_code_lens(
      999,
      1,
      "invalid",
      command=browser_code_lens_command("fixture.invalid", "invalid"),
    ),
  ]
  if self.mode.val == 1 {
    result.push(
      browser_code_lens(
        10,
        3,
        "expanded-10",
        command=browser_code_lens_command("fixture.ten", "ten"),
      ),
    )
    result.push(
      browser_code_lens(
        20,
        7,
        "expanded-20",
        command=browser_code_lens_command("fixture.twenty", "twenty"),
      ),
    )
  }
  result
}

///|
priv struct BrowserCodeLensResolver {
  calls : Array[String]
}

///|
impl @language.CodeLensResolver for BrowserCodeLensResolver with fn resolve_code_lens(
  self,
  _model,
  lens,
  _token,
) {
  guard lens.id is Some(id) else { return None }
  self.calls.push(id)
  @js.suspend((resolve : (Unit) -> Unit, _reject : (Error) -> Unit) => {
    @support.set_timeout(() => resolve(()), 80)
  }) catch {
    _ => ()
  }
  Some({
    ..lens,
    command: Some(
      browser_code_lens_command(
        "fixture.\{id}",
        "resolved \{id}",
        tooltip="Resolved lazily",
      ),
    ),
  })
}

///|
priv struct PlainCodeLensProvider {}

///|
impl @language.CodeLensProvider for PlainCodeLensProvider with fn provide_code_lenses(
  _self,
  _model,
  _token,
) {
  [
    browser_code_lens(
      1,
      1,
      "plain",
      command=browser_code_lens_command(
        "fixture.plain", "plain without executor",
      ),
    ),
  ]
}

///|
fn code_lens_request_json(
  request : @code_lens_api.CodeLensCommandRequest,
) -> Json {
  Json({
    "sourceViewerId": request.source_viewer_id.to_json(),
    "resource": request.resource.to_string().to_json(),
    "startLine": request.range.start_line_number.to_json(),
    "startColumn": request.range.start_column.to_json(),
    "endLine": request.range.end_line_number.to_json(),
    "endColumn": request.range.end_column.to_json(),
    "id": request.command.id.to_json(),
    "title": request.command.title.to_json(),
    "tooltip": match request.command.tooltip {
      Some(tooltip) => tooltip.to_json()
      None => Json::null()
    },
    "arguments": Json(request.command.arguments),
  })
}

///|
pub fn run_code_lens_test() -> Unit {
  let ctx = @support.BrowserTestContext("code_lens")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell code-lens-shell")
  shell.set_attribute("data-theme", "dark")
  let main_host = document.create_element("div")
  main_host.set_attribute("class", "viewer-host code-lens-main-host")
  main_host.set_attribute("style", "height:190px;width:760px;")
  let plain_host = document.create_element("div")
  plain_host.set_attribute("class", "viewer-host code-lens-plain-host")
  plain_host.set_attribute("style", "height:80px;width:760px;margin-top:12px;")
  shell.append_child(main_host.as_node())
  shell.append_child(plain_host.as_node())
  app.append_child(shell.as_node())

  let log_service = @log.LogService()
  let languages = @languages.Languages()
  let mode = Ref(0)
  let provider_calls = Ref(0)
  let resolve_calls : Array[String] = []
  let changes : @base_common.Emitter[Unit] = @base_common.Emitter()
  languages.register_code_lens_provider(
    LanguageId("codelens-main"),
    BrowserCodeLensProvider::{ mode, calls: provider_calls, },
    resolver=BrowserCodeLensResolver::{ calls: resolve_calls, },
    on_did_change=callback => changes.event(_ => callback()),
  )
  |> ignore
  languages.register_code_lens_provider(LanguageId("codelens-plain"), PlainCodeLensProvider::{
  })
  |> ignore
  let executions : Array[@code_lens_api.CodeLensCommandRequest] = []
  let executor = @code_lens_api.CodeLensCommandExecutorHandle(execute=request => {
    executions.push(request)
    true
  })
  let main_services = @viewer.ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    code_lens_command_executor=executor,
    log_service=log_service.log_handle(),
  )
  let plain_services = @viewer.ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  let main_model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/code-lens-main.mbt",
    ),
    "code-lens-main.mbt",
    "codelens-main",
    1,
    "code-lens-main-revision",
    browser_code_lens_source(),
  )
  let plain_model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/code-lens-plain.mbt",
    ),
    "code-lens-plain.mbt",
    "codelens-plain",
    1,
    "code-lens-plain-revision",
    "plain_source",
  )
  let main_viewer = @viewer.Viewer::create(
    main_host,
    services=main_services,
    options=ViewerOptions(font_size=20, line_height=28),
  )
  let plain_viewer = @viewer.Viewer::create(
    plain_host,
    services=plain_services,
    options=ViewerOptions(code_lens_font_family="serif", code_lens_font_size=11),
  )
  main_viewer.set_model(Some(main_model))
  plain_viewer.set_model(Some(plain_model))
  main_viewer.handle_initialized()
  plain_viewer.handle_initialized()
  install_code_lens_controls(
    () => {
      Json({
        "providerCalls": provider_calls.val.to_json(),
        "resolveCalls": Json(resolve_calls.map(call => call.to_json())),
        "executions": Json(
          executions.map(request => code_lens_request_json(request)),
        ),
        "scrollTop": Json::number(main_viewer.get_scroll_top()),
        "scrollHeight": Json::number(main_viewer.get_scroll_height()),
        "top40": Json::number(
          main_viewer.get_top_for_line_number(40, include_view_zones=true),
        ),
        "expanded": (mode.val == 1).to_json(),
      }).stringify()
    },
    () => {
      mode.val = 1
      changes.fire(())
    },
    () => {
      mode.val = 0
      changes.fire(())
    },
    () => {
      let top = main_viewer.get_top_for_line_number(40, include_view_zones=true)
      main_viewer.set_scroll_top((top - 30.0).max(0.0))
    },
    enabled => {
      main_viewer.update_options(
        main_viewer.get_options().with_code_lens(enabled),
      )
    },
  )
  poll_code_lens_ready(ctx, 160)
}

///|
fn poll_code_lens_ready(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  let main_ready = @support.query_count(
      ".code-lens-main-host .codelens-decoration[data-code-lens-line=\"2\"]",
    ) ==
    1
  let plain_ready = @support.query_count(
      ".code-lens-plain-host .codelens-decoration[data-code-lens-line=\"1\"]",
    ) ==
    1
  if main_ready && plain_ready && code_lens_controls_installed() {
    ctx.metric_int(
      "initialRows",
      @support.query_count(".code-lens-main-host .codelens-decoration"),
    )
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for CodeLens fixture")
    ctx.finish()
  } else {
    @support.set_timeout(() => poll_code_lens_ready(ctx, remaining - 1), 30)
  }
}

///|
extern "js" fn code_lens_controls_installed() -> Bool =
  #| () => Boolean(globalThis.__codeLensControls)

///|
extern "js" fn install_code_lens_controls(
  state_json : () -> String,
  expand : () -> Unit,
  collapse : () -> Unit,
  scroll_late : () -> Unit,
  set_enabled : (Bool) -> Unit,
) -> Unit =
  #| (stateJson, expand, collapse, scrollLate, setEnabled) => {
  #|   globalThis.__codeLensControls = {
  #|     state: () => JSON.parse(stateJson()),
  #|     expand,
  #|     collapse,
  #|     scroll_late: scrollLate,
  #|     set_enabled: setEnabled,
  #|   };
  #| }
