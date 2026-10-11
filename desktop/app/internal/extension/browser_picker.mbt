///|
priv struct BrowserPick {
  id : Int
  request : String
  token : String
  mut task : @async.Task[@protocol.BrowserPickReply]?
}

///|
fn BrowserViews::cancel_pick(self : BrowserViews) -> Unit {
  if self.pick is Some(pick) {
    self.pick = None
    if pick.task is Some(task) {
      task.cancel()
    }
  }
}

///|
async fn BrowserViews::pick_element(
  self : BrowserViews,
  payload : @protocol.BrowserPickPayload,
) -> @protocol.BrowserPickReply {
  self.cancel_pick()
  let token = @uuid.mint()
  let pick : BrowserPick = {
    token,
    id: payload.id,
    request: payload.request,
    task: None,
  }
  self.pick = Some(pick)
  defer {
    pick.task = None
    if self.pick is Some(current) && current.token == pick.token {
      self.pick = None
    }
  }
  @async.with_task_group(group => {
    let task : @async.Task[@protocol.BrowserPickReply] = group.spawn(
      () => {
        @async.with_timeout(120000, () => {
          self.with_cdp(payload.id, connection => {
            guard self.pick is Some(current) && current.token == pick.token else {
              return Cancelled
            }
            self.inspect_element(pick, connection)
          })
        })
      },
      allow_failure=true,
    )
    pick.task = Some(task)
    task.wait()
  }) catch {
    _ if !(self.pick is Some(current) && current.token == pick.token) =>
      Cancelled
    error => raise error
  }
}

///|
/// Run selection on the connected page and clean up its Escape listener.
async fn BrowserViews::inspect_element(
  self : BrowserViews,
  pick : BrowserPick,
  connection : @cdp.Connection,
) -> @protocol.BrowserPickReply {
  let binding = "__seekmoon_cancel_" + pick.token
  let binding_json = binding.to_json().stringify()
  let listener_json = (binding + "_listener").to_json().stringify()
  defer (self
    .view(pick.id)
    .eval(
      "globalThis[\{listener_json}]?.abort(); delete globalThis[\{listener_json}]; delete globalThis[\{binding_json}];",
    ) catch {
      _ => ()
    })
  // CEF leaves Escape to the page when there is no DevTools frontend.
  // This binding only cancels this capture; it exposes no host commands.
  connection.add_binding(binding)
  let install_listener =
    $|(() => {
    $|  const controller = new AbortController();
    $|  globalThis[\{listener_json}] = controller;
    $|  addEventListener('keydown', e => {
    $|    if (e.key !== 'Escape' || e.isComposing) return;
    $|    e.preventDefault();
    $|    e.stopImmediatePropagation();
    $|    globalThis[\{binding_json}]('cancel');
    $|    controller.abort();
    $|  }, {capture:true, signal:controller.signal});
    $|  return true;
    $|})()
  let _ : Bool = connection.evaluate(install_listener).decode_value()
  connection.enable_dom()
  connection.enable_overlay()
  connection.set_inspect_mode(SearchForNode(@cdp.devtools_highlight()))
  self.view(pick.id).focus()
  for ;; {
    let node = match connection.next_event() {
      BindingCalled(name~, ..) if name == binding => return Cancelled
      InspectModeCanceled => return Cancelled
      InspectNodeRequested(node) => node
      _ => continue
    }
    connection.set_inspect_mode(Disabled)
    connection.hide_highlight()
    let object = connection.resolve_node(node)
    guard object.object_id is Some(object_id) else {
      raise BrowserCaptureError("Selected element is no longer available")
    }
    let result = connection.call_function_on({
      object_id,
      declaration: browser_element_script,
    })
    let element : @protocol.BrowserElement = result.decode_value()
    connection.release_object(object_id)
    self.attached_window().browser().focus()
    return Selected(element)
  }
}

///|
let browser_element_script : String =
  #|function() {
  #|  const el = this.nodeType === 1 ? this : this.parentElement;
  #|  if (!el) throw new Error('Element is no longer available');
  #|  const doc = el.ownerDocument;
  #|  let selector = null;
  #|  if (el.id) {
  #|    const candidate = '#' + CSS.escape(el.id);
  #|    if (doc.querySelectorAll(candidate).length === 1 && doc.querySelector(candidate) === el) selector = candidate;
  #|  }
  #|  if (!selector && el.getRootNode() === doc) {
  #|    const parts = []; let node = el;
  #|    while (node && parts.length < 12) {
  #|      let part = node.localName;
  #|      if (!part) break;
  #|      const siblings = node.parentElement ? [...node.parentElement.children].filter(x => x.localName === node.localName) : [];
  #|      if (siblings.length > 1) part += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';
  #|      parts.unshift(part); node = node.parentElement;
  #|    }
  #|    const candidate = parts.join(' > ');
  #|    if (candidate && doc.querySelectorAll(candidate).length === 1 && doc.querySelector(candidate) === el) selector = candidate;
  #|  }
  #|  return {url:doc.URL, title:doc.title, tag:el.localName, selector,
  #|    text:(el.innerText || el.textContent || '').slice(0,8000),
  #|    html:el.outerHTML.slice(0,12000)};
  #|}

///|
async test "cancelling a pick terminates its pending reader before another pick starts" {
  let views = BrowserViews()
  let mut started = false
  let mut cleaned = false
  @async.with_task_group(group => {
    let task : @async.Task[@protocol.BrowserPickReply] = group.spawn(
      () => {
        defer {
          cleaned = true
        }
        started = true
        @async.sleep(60000)
        Cancelled
      },
      allow_failure=true,
    )
    let pick : BrowserPick = {
      id: 1,
      request: "one",
      token: @uuid.mint(),
      task: Some(task),
    }
    views.pick = Some(pick)
    while !started {
      @async.sleep(1)
    }
    views.cancel_pick()
    let cancelled = try {
      ignore(task.wait())
      false
    } catch {
      @async.WaitedTaskAlreadyCancelled => true
      error => raise error
    }
    assert_true(cancelled)
    assert_true(cleaned)
    assert_true(views.pick is None)
  })
}
