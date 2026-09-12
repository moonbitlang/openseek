// In-page scenario for the agent-feedback contrib: enables feedback on the
// fixture resource, seeds two nearby items (one bubble group) plus one far
// item (its own bubble), and asserts the collapsed bubbles mount with the
// reserved gutter lane. The interactive flow (hover "+" glyph → inline
// input → add, expand/collapse, reply, edit, remove, scroll tracking) is
// driven by the paired Playwright spec
// (`tests/browser/component/agent_feedback.spec.js`) with real mouse and
// keyboard input; service events are mirrored onto `#feedback-events` data
// attributes so the spec can observe host-persistence facts.

///|
pub fn run_agent_feedback_test() -> Unit {
  let ctx = @support.BrowserTestContext("agent_feedback")
  let done = Ref(false)
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/feedback.mbt",
  )
  let model = @model.TextModel(
    uri,
    "feedback.mbt",
    "moonbit",
    1,
    "feedback-rev-1",
    feedback_source_text(),
  )
  match mount_host() {
    Some((host, event_log)) => {
      // The page owns the concrete store for the lifetime of this interactive
      // fixture. Viewer receives only its narrowed callback capability.
      let feedback = @feedback_contrib.AgentFeedbackService()
      let feedback_handle = feedback.agent_feedback_handle()
      let services = @viewer.ViewerServices(agent_feedback=feedback_handle)
      let added = Ref(0)
      let replies = Ref(0)
      let submitted = Ref(0)
      let items = Ref(0)
      let mut last_text : String = ""
      let mut previous_items : Array[
        (String, @agent_feedback_api.AgentFeedbackState, Int),
      ] = []
      let mut track_interactions = false
      let write_log = () => {
        event_log.set_attribute("data-added", added.val.to_string())
        event_log.set_attribute("data-replies", replies.val.to_string())
        event_log.set_attribute("data-submitted", submitted.val.to_string())
        event_log.set_attribute("data-items", items.val.to_string())
        event_log.set_attribute("data-last-text", last_text)
      }
      feedback_handle.on_did_change_feedback(event => {
        if track_interactions {
          for item in event.feedback_items {
            match previous_items.search_by(snapshot => snapshot.0 == item.id) {
              Some(index) => {
                let (_, previous_state, previous_reply_count) = previous_items[index]
                if item.replies.length() > previous_reply_count {
                  replies.val += item.replies.length() - previous_reply_count
                }
                if previous_state == Accepted && item.state == Submitted {
                  submitted.val += 1
                }
              }
              None => if item.state == Accepted { added.val += 1 }
            }
          }
        }
        items.val = event.feedback_items.length()
        last_text = match event.feedback_items.last() {
          Some(item) => item.text
          None => last_text
        }
        previous_items = event.feedback_items.map(item => {
          (item.id, item.state, item.replies.length())
        })
        write_log()
      })
      |> ignore
      write_log()
      // Seed the store before the model attaches: `set_model`'s rebuild must
      // pick the data up.
      feedback.set_feedback_enabled(uri, true)
      feedback.set_feedback_items(uri, [
        seed_item("seed-1", uri, 3, "First seeded note"),
        seed_item("seed-2", uri, 5, "Second seeded note"),
        seed_item("seed-far", uri, 30, "Far seeded note"),
      ])
      track_interactions = true
      let viewer = @viewer.Viewer::create(
        host,
        services~,
        options=ViewerOptions(placeholder="Loading feedback fixture..."),
      )
      viewer.set_model(Some(model))
      viewer.handle_initialized()
      @support.set_timeout(() => poll_rendered(ctx, done, 80), 50)
    }
    None => {
      ctx.fail("missing #app mount point")
      ctx.finish()
    }
  }
}

///|
fn seed_item(
  id : String,
  uri : @base_common.Uri,
  line : Int,
  text : String,
) -> @agent_feedback_api.AgentFeedback {
  {
    id,
    text,
    resource: uri,
    range: Range(line, 1, line, 8),
    kind: UserReview,
    replies: [],
    state: Accepted,
  }
}

///|
fn poll_rendered(
  ctx : @support.BrowserTestContext,
  done : Ref[Bool],
  remaining : Int,
) -> Unit {
  if done.val {
    return
  }
  let widgets = @support.query_count(".agent-feedback-widget")
  if widgets >= 2 {
    ctx.assert_true(widgets == 2, "expected two bubble groups")
    ctx.assert_true(
      @support.query_count(".agent-feedback-widget.collapsed") == 2,
      "bubbles must mount collapsed",
    )
    ctx.assert_true(
      @support.query_count(".agent-feedback-widget-item") == 3,
      "expected three comment items across the bubbles",
    )
    ctx.metric_int("widgets", widgets)
    ctx.metric_int(
      "collapsed",
      @support.query_count(".agent-feedback-widget.collapsed"),
    )
    done.val = true
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for feedback bubbles")
    done.val = true
    ctx.finish()
  } else {
    @support.set_timeout(() => poll_rendered(ctx, done, remaining - 1), 50)
  }
}

///|
fn mount_host() -> (@rdom.Element, @rdom.Element)? {
  let document = @rdom.document()
  match document.query_selector("#app").to_option() {
    Some(app) => {
      let shell = document.create_element("main")
      shell.set_attribute("class", "editor-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = document.create_element("div")
      host.set_attribute("class", "viewer-host")
      host.set_attribute("style", "height:360px;width:640px;")
      let event_log = document.create_element("div")
      event_log.set_attribute("id", "feedback-events")
      shell.append_child(host.as_node())
      shell.append_child(event_log.as_node())
      app.append_child(shell.as_node())
      Some((host, event_log))
    }
    None => None
  }
}

///|
fn feedback_source_text() -> String {
  // Filler pushes the content past the 360px host so the scroll-tracking
  // spec step has room to wheel; line 30 anchors the far bubble.
  let filler = StringBuilder()
  for index in 1..<=34 {
    filler <+ "// filler line \{index}\n"
  }
  (
    #|// feedback fixture
    #|fn reviewed_area() -> Int {
    #|  let alpha = 1
    #|  let beta = 2
    #|  alpha + beta
    #|}
    #|
    #|fn quiet_area() -> Unit {
    #|  let untouched = "no feedback here"
    #|  ignore(untouched)
    #|}
    #|// end of fixture
    #|
  ) +
  filler.to_string()
}
