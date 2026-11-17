///|
const ARTIFACT_FRAME_POLICY = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"

///|
/// Runs inside the frame before the artifact, with `token` bound by
/// `artifact_srcdoc`. Serializes inside the frame, so the parent only
/// receives a string and validates it as JSON. State that is not plain JSON
/// data posts no payload.
let artifact_frame_bridge : String =
  #|const plain = value => {
  #|  const type = typeof value;
  #|  if (value === null || type === "string" || type === "boolean") return true;
  #|  if (type === "number") return Number.isFinite(value);
  #|  if (type !== "object") return false;
  #|  const proto = Object.getPrototypeOf(value);
  #|  return Array.isArray(value) || proto === Object.prototype || proto === null;
  #|};
  #|window.openseekArtifact = {
  #|  setState: (title, state) => {
  #|    let payload = null;
  #|    try {
  #|      payload = JSON.stringify({ title, state }, (_key, value) => {
  #|        if (plain(value)) return value;
  #|        throw new TypeError("Component state must be JSON data");
  #|      });
  #|    } catch {}
  #|    parent.postMessage({ type: "openseek-artifact-state", version: 2, token, payload }, "*");
  #|  },
  #|};

///|
let artifact_frame_followup : String =
  #|window.openseekArtifact.sendFollowUpMessage = ({ prompt, title = "" }) => {
  #|  parent.postMessage({ type: "openseek-artifact-followup", version: 2, token, prompt, title }, "*");
  #|};

///|
/// Runs inside the frame after the artifact and reports its height.
let artifact_frame_resize : String =
  #|const send = () => parent.postMessage({
  #|  type: "openseek-artifact-height",
  #|  height: Math.ceil(document.body?.scrollHeight || 420),
  #|}, "*");
  #|addEventListener("load", () => {
  #|  new ResizeObserver(send).observe(document.body);
  #|  send();
  #|});

///|
fn artifact_srcdoc(
  content : String,
  token : String,
  followup_enabled~ : Bool,
) -> String {
  let token = Json::string(token).stringify()
  let followup = if followup_enabled { artifact_frame_followup } else { "" }
  "<meta http-equiv=\"Content-Security-Policy\" content=\"\{ARTIFACT_FRAME_POLICY}\"><meta name=\"referrer\" content=\"no-referrer\">" +
  "<script>(() => {\nconst token = \{token};\n\{artifact_frame_bridge}\n\{followup}\n})();</script>" +
  content +
  "<script>(() => {\n\{artifact_frame_resize}\n})();</script>"
}

///|
fn is_hidden(element : @dom.Element) -> Bool {
  element.to_html_element() is Some(element) &&
  element.get_style().get_property_value("display") == "none"
}

///|
/// An empty `display` removes the inline value.
fn set_display(element : @dom.Element, display : String) -> Unit {
  if element.to_html_element() is Some(element) {
    element.get_style().set_property("display", display)
  }
}

///|
fn settle_artifact_frames(
  reference : String,
  state : ArtifactFileState,
  owner : String,
  followup_enabled~ : Bool,
) -> Unit {
  for node in @dom.document().query_selector_all("[data-transcript-artifact]") {
    guard node.get_attribute("data-transcript-artifact") == Some(reference) &&
      node.get_attribute("data-artifact-owner") == Some(owner) &&
      node.query_selector("iframe") is Some(frame) else {
      continue
    }
    if frame.get_attribute("data-artifact-loaded") == Some(owner) &&
      frame.get_attribute("data-artifact-reference") == Some(reference) {
      continue
    }
    let button = node.query_selector(".chat-artifact-context")
    if frame.has_attribute("data-artifact-loaded") {
      frame.remove_attribute("srcdoc")
      frame.remove_attribute("data-artifact-loaded")
      frame.remove_attribute("data-artifact-reference")
      frame.remove_attribute("data-artifact-token")
      set_display(frame, "none")
      if button is Some(button) {
        set_display(button, "none")
      }
    }
    let fallback = node.query_selector("[data-artifact-fallback]")
    let show_fallback = () => {
      if fallback is Some(fallback) && is_hidden(fallback) {
        set_display(fallback, "")
      }
    }
    match state {
      ReadyArtifact(content) => {
        let token = @uuid.mint()
        frame.set_attribute("data-artifact-token", token)
        if button is Some(button) {
          set_display(button, "none")
        }
        frame.set_attribute(
          "srcdoc",
          artifact_srcdoc(content, token, followup_enabled~),
        )
        frame.set_attribute("data-artifact-loaded", owner)
        frame.set_attribute("data-artifact-reference", reference)
        set_display(frame, "block")
        if fallback is Some(fallback) {
          set_display(fallback, "none")
        }
      }
      FailedArtifact(error) => {
        if node.get_attribute("title") != Some(error) {
          node.set_attribute("title", error)
        }
        show_fallback()
      }
      LoadingArtifact => show_fallback()
    }
  }
}

///|
priv enum ArtifactFrameMessage {
  ArtifactHeight(Int32)
  /// `payload` is absent when the frame could not serialize its state.
  ArtifactState(token~ : String, payload~ : String?)
  ArtifactFollowup(token~ : String, prompt~ : String, title~ : String)
}

///|
fn ArtifactFrameMessage::decode(data : @js.Value) -> ArtifactFrameMessage? {
  guard data.is_object() && !data.is_null() else { return None }
  let string = (name : String) => {
    let value : @js.Value = data.get_with_string(name)
    if value.is_string() {
      Some(value.cast())
    } else {
      None
    }
  }
  let number = (name : String) => {
    let value : @js.Value = data.get_with_string(name)
    if value.is_number() {
      let value : Double = value.cast()
      if value.is_nan() || value.is_inf() {
        None
      } else {
        Some(value)
      }
    } else {
      None
    }
  }
  match string("type") {
    Some("openseek-artifact-height") =>
      number("height").map(height => {
        ArtifactHeight(height.ceil().clamp(min=64.0, max=2000.0).to_int())
      })
    Some("openseek-artifact-state") => {
      guard number("version") == Some(2.0) && string("token") is Some(token) else {
        return None
      }
      Some(ArtifactState(token~, payload=string("payload")))
    }
    Some("openseek-artifact-followup") => {
      guard number("version") == Some(2.0) &&
        string("token") is Some(token) &&
        string("prompt") is Some(prompt) &&
        string("title") is Some(title) else {
        return None
      }
      let prompt = prompt.trim()
      guard !prompt.is_empty() else { return None }
      Some(
        ArtifactFollowup(
          token~,
          prompt=prompt.to_owned(),
          title=title.trim().to_owned(),
        ),
      )
    }
    _ => None
  }
}

///|
fn source_frame(root_id : String, event : @dom.Event) -> @dom.Element? {
  for
    frame in @dom.document().query_selector_all(
      "#\{root_id} .chat-artifact-frame",
    ) {
    if message_from_frame(event, frame) {
      return Some(frame)
    }
  }
  None
}

///|
fn current_artifact_frame(
  frame : @dom.Element,
  token : String,
) -> (@dom.Element, String, String)? {
  guard frame.get_attribute("data-artifact-token") == Some(token) &&
    frame.closest("[data-transcript-artifact]") is Some(node) &&
    node.get_attribute("data-transcript-artifact") is Some(reference) &&
    node.get_attribute("data-artifact-owner") is Some(owner) &&
    frame.get_attribute("data-artifact-reference") == Some(reference) &&
    frame.get_attribute("data-artifact-loaded") == Some(owner) else {
    return None
  }
  Some((node, reference, owner))
}

///|
/// Installs the frame message and selection listeners of the transcript
/// whose scroller is `root_id`. Returns the uninstaller.
fn artifact_frame_listener(
  root_id : String,
  changed : () -> Unit,
  interact : (String, ArtifactInteraction) -> Unit,
) -> () -> Unit {
  // Keyed by frame generation token; a reloaded frame gets a new token, so
  // a stale entry is never read again.
  let snapshots : Map[String, @mention_context.ArtifactSnapshot] = Map([])
  let message : @dom.Listener = event => {
    guard event.to_message_event() is Some(message_event) &&
      ArtifactFrameMessage::decode(message_event.get_data()) is Some(message) &&
      source_frame(root_id, event) is Some(frame) else {
      return
    }
    match message {
      ArtifactHeight(height) => {
        let height = "\{height}px"
        if frame.to_html_element() is Some(frame) &&
          frame.get_style().get_property_value("height") != height {
          frame.get_style().set_property("height", height)
          changed()
        }
      }
      ArtifactState(token~, payload~) => {
        guard current_artifact_frame(frame, token) is Some((node, reference, _)) else {
          return
        }
        let button = node.query_selector(".chat-artifact-context")
        if payload is Some(payload) &&
          @mention_context.artifact_snapshot(reference, payload)
          is Some(snapshot) {
          snapshots[token] = snapshot
          if button is Some(button) &&
            !button.has_attribute("disabled") &&
            is_hidden(button) {
            set_display(button, "")
          }
        } else {
          snapshots.remove(token)
          if button is Some(button) && !is_hidden(button) {
            set_display(button, "none")
          }
        }
      }
      ArtifactFollowup(token~, prompt~, title~) => {
        guard current_artifact_frame(frame, token) is Some((_, _, owner)) &&
          frame_has_user_activation(frame) else {
          return
        }
        interact(
          owner,
          RequestFollowup(prompt~, title~, snapshot=snapshots.get(token)),
        )
      }
    }
  }
  let click : @dom.Listener = event => {
    guard event_is_trusted(event) &&
      event.target().to_element() is Some(target) &&
      target.closest("#\{root_id} .chat-artifact-context") is Some(button) &&
      !button.has_attribute("disabled") &&
      button.closest("[data-transcript-artifact]") is Some(node) &&
      node.query_selector("iframe") is Some(frame) &&
      node.get_attribute("data-artifact-owner") is Some(owner) &&
      frame.get_attribute("data-artifact-loaded") == Some(owner) &&
      frame.get_attribute("data-artifact-reference") ==
      node.get_attribute("data-transcript-artifact") &&
      frame.get_attribute("data-artifact-token") is Some(token) &&
      snapshots.get(token) is Some(snapshot) else {
      return
    }
    interact(owner, AttachState(snapshot))
  }
  @dom.window().add_event_listener("message", message)
  @dom.document().add_event_listener("click", click)
  () => {
    @dom.window().remove_event_listener("message", message)
    @dom.document().as_event_target().remove_event_listener("click", click)
  }
}

///|
/// `MessageEvent.source` and `HTMLIFrameElement.contentWindow` have no
/// Rabbita bindings.
extern "js" fn message_from_frame(
  event : @dom.Event,
  frame : @dom.Element,
) -> Bool =
  #|(event, frame) => event.source === frame.contentWindow

///|
extern "js" fn event_is_trusted(event : @dom.Event) -> Bool =
  #|(event) => event.isTrusted

///|
extern "js" fn frame_has_user_activation(frame : @dom.Element) -> Bool =
  #|frame => document.activeElement === frame && navigator.userActivation?.isActive === true
