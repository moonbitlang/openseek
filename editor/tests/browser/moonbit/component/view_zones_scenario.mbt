// Real-Chromium fixture for ViewZone DOM ownership, offscreen geometry, and
// native mouse suppression. State-machine and lifecycle matrices live in the
// owning MoonBit white-box packages.

///|
fn view_zones_source_with_line_count(line_count : Int) -> String {
  let text = StringBuilder()
  for line in 1..<=line_count {
    if line > 1 {
      text.write_char('\n')
    }
    text <+ "view_zone_line_\{line}"
  }
  text.to_string()
}

///|
fn view_zones_source() -> String {
  view_zones_source_with_line_count(80)
}

///|
pub fn run_view_zones_test() -> Unit {
  let ctx = @support.BrowserTestContext("view_zones")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }

  let focus_sink = document.create_element("button")
  focus_sink.set_attribute("class", "view-zones-focus-sink")
  focus_sink.set_inner_html("outside focus sink")
  app.append_child(focus_sink.as_node())
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host view-zones-host")
  host.set_attribute("style", "height:260px;width:320px;")
  app.append_child(host.as_node())

  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/view-zones.txt",
  )
  let model = @model.TextModel(
    uri,
    "view-zones.txt",
    "plaintext",
    1,
    "view-zones-rev-1",
    view_zones_source(),
  )
  let viewer = @viewer.Viewer::create(host)
  let mut public_mouse_events = 0
  let mut public_mouse_target_id = ""
  let mut public_mouse_target_kind = "other"
  viewer.on_mouse_down(event => {
    public_mouse_events += 1
    match event.target {
      MouseTargetViewZone(type_~, detail~, ..) => {
        public_mouse_target_id = detail.view_zone_id
        public_mouse_target_kind = match type_ {
          ContentViewZone => "content"
          GutterViewZone => "gutter"
          _ => "other"
        }
      }
      _ => {
        public_mouse_target_id = ""
        public_mouse_target_kind = "other"
      }
    }
  })
  |> ignore
  viewer.set_model(Some(model))
  viewer.handle_initialized()

  let primary_node = document.create_element("div")
  primary_node.set_attribute("class", "vz-primary host-primary preserved-class")
  primary_node.set_attribute(
    "style", "color:rgb(1,2,3);border-left:3px solid rgb(4,5,6);padding-left:7px;position:relative;width:37px;display:inline;top:7px;height:9px;",
  )
  primary_node.set_attribute("data-caller-owned", "primary")
  let primary_child = document.create_element("span")
  primary_child.set_attribute("class", "vz-primary-child")
  primary_child.set_attribute("data-caller-state", "preserved")
  primary_child.set_inner_html("preserved descendant")
  primary_node.append_child(primary_child.as_node())
  let primary_margin = document.create_element("div")
  primary_margin.set_attribute(
    "class", "vz-primary-margin host-margin preserved-margin-class",
  )
  primary_margin.set_attribute(
    "style", "background-color:rgb(7,8,9);border-right:2px solid rgb(10,11,12);position:relative;width:19px;display:inline;top:4px;height:8px;",
  )
  primary_margin.set_attribute("data-caller-owned", "margin")
  primary_margin.set_inner_html("preserved margin content")

  let mut primary_last_top = -2000000.0
  let primary = @viewer.view_zone(
    1,
    primary_node,
    ordinal=20,
    height_in_px=32.0,
    min_width_in_px=700.0,
    margin_dom_node=primary_margin,
    on_dom_node_top=top => primary_last_top = top,
  )

  let secondary_node = document.create_element("div")
  secondary_node.set_attribute("class", "vz-secondary")
  secondary_node.set_inner_html("same-anchor lower ordinal")
  let secondary = @viewer.view_zone(
    1,
    secondary_node,
    ordinal=-10,
    height_in_px=20.0,
  )

  let suppress_node = document.create_element("div")
  suppress_node.set_attribute("class", "vz-suppress")
  suppress_node.set_inner_html("suppress mouse down content")
  let suppress_margin = document.create_element("div")
  suppress_margin.set_attribute("class", "vz-suppress-margin")
  suppress_margin.set_inner_html("suppress mouse down gutter")
  let suppress_zone = @viewer.view_zone(
    3,
    suppress_node,
    ordinal=50,
    suppress_mouse_down=true,
    height_in_px=32.0,
    margin_dom_node=suppress_margin,
  )

  let omitted_node = document.create_element("div")
  omitted_node.set_attribute("class", "vz-omitted-suppress")
  omitted_node.set_inner_html("omitted suppress mouse down")
  let omitted_zone = @viewer.view_zone(0, omitted_node, height_in_px=24.0)

  let offscreen_node = document.create_element("div")
  offscreen_node.set_attribute("class", "vz-offscreen")
  offscreen_node.set_inner_html("offscreen view zone")
  let mut offscreen_last_top = -2000000.0
  let offscreen_zone = @viewer.view_zone(
    40,
    offscreen_node,
    height_in_px=28.0,
    on_dom_node_top=top => offscreen_last_top = top,
  )

  let mut primary_id = ""
  let mut suppress_id = ""
  let mut omitted_id = ""
  viewer.change_view_zones(accessor => {
    primary_id = accessor.add_zone(primary)
    accessor.add_zone(secondary) |> ignore
    suppress_id = accessor.add_zone(suppress_zone)
    omitted_id = accessor.add_zone(omitted_zone)
    accessor.add_zone(offscreen_zone) |> ignore
  })

  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("missing live View root")
    ctx.finish()
    return
  }
  install_view_zones_controls(
    root,
    focus_sink,
    primary_node,
    primary_child,
    primary_margin,
    () => {
      let layout = viewer.get_layout_info()
      Json({
        "primaryId": primary_id.to_json(),
        "suppressId": suppress_id.to_json(),
        "omittedId": omitted_id.to_json(),
        "mouseEvents": public_mouse_events.to_json(),
        "mouseTargetId": public_mouse_target_id.to_json(),
        "mouseTargetKind": public_mouse_target_kind.to_json(),
        "primaryLastTop": Json::number(primary_last_top),
        "offscreenLastTop": Json::number(offscreen_last_top),
        "scrollTop": Json::number(viewer.get_scroll_top()),
        "scrollWidth": Json::number(viewer.get_scroll_width()),
        "contentWidth": Json::number(viewer.get_content_width()),
        "contentLeft": Json::number(layout.content_left),
      }).stringify()
    },
    scroll_top => viewer.set_scroll_top(scroll_top),
    () => {
      let top = viewer.get_top_for_line_number(40, include_view_zones=true)
      viewer.set_scroll_top(top)
    },
    suppress => suppress_zone.suppress_mouse_down = Some(suppress),
    suppress => primary.suppress_mouse_down = Some(suppress),
  )
  poll_view_zones_ready(ctx, 120)
}

///|
fn poll_view_zones_ready(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  let primary_visible = @support.query_count(
      ".view-zones-host .vz-primary[monaco-visible-view-zone]",
    ) ==
    1
  let controls_ready = view_zones_controls_installed()
  if primary_visible && controls_ready {
    ctx.metric_int(
      "registeredZones",
      @support.query_count(".view-zones-host [monaco-view-zone]"),
    )
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for ViewZones fixture")
    ctx.finish()
  } else {
    @support.set_timeout(() => poll_view_zones_ready(ctx, remaining - 1), 30)
  }
}

///|
extern "js" fn view_zones_controls_installed() -> Bool =
  #| () => Boolean(globalThis.__viewZonesControls)

///|
extern "js" fn install_view_zones_controls(
  root : @rdom.Element,
  focus_sink : @rdom.Element,
  primary : @rdom.Element,
  primary_child : @rdom.Element,
  primary_margin : @rdom.Element,
  state_json : () -> String,
  set_scroll_top : (Double) -> Unit,
  show_offscreen : () -> Unit,
  set_suppress : (Bool) -> Unit,
  set_primary_suppress : (Bool) -> Unit,
) -> Unit =
  #| (root, focusSink, primary, primaryChild, primaryMargin, stateJson,
  #|  setScrollTop, showOffscreen, setSuppress, setPrimarySuppress) => {
  #|   primary.__callerState = { retained: true };
  #|   primaryChild.__callerState = { retained: true };
  #|   primaryMargin.__callerState = { retained: true };
  #|   let primaryClicks = 0;
  #|   let childClicks = 0;
  #|   let marginClicks = 0;
  #|   primary.addEventListener('click', () => { primaryClicks += 1; });
  #|   primaryChild.addEventListener('click', () => { childClicks += 1; });
  #|   primaryMargin.addEventListener('click', () => { marginClicks += 1; });
  #|   const mouseRecords = [];
  #|   root.addEventListener('mousedown', (event) => {
  #|     const zone = event.target.closest?.('[monaco-view-zone]');
  #|     mouseRecords.push({
  #|       button: event.button,
  #|       defaultPrevented: event.defaultPrevented,
  #|       activeRoot: document.activeElement === root,
  #|       zoneId: zone?.getAttribute('monaco-view-zone') ?? '',
  #|       margin: Boolean(zone?.closest('.margin-view-zones')),
  #|     });
  #|   });
  #|   globalThis.__viewZonesControls = {
  #|     state: () => JSON.parse(stateJson()),
  #|     set_scroll_top: setScrollTop,
  #|     show_offscreen: showOffscreen,
  #|     set_suppress: setSuppress,
  #|     set_primary_suppress: setPrimarySuppress,
  #|     focus_sink: () => focusSink.focus(),
  #|     clear_mouse: () => { mouseRecords.length = 0; },
  #|     mouse_records: () => [...mouseRecords],
  #|     click_counts: () => ({ primary: primaryClicks, child: childClicks, margin: marginClicks }),
  #|   };
  #| }
