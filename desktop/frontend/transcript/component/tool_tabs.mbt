// A compact, state-free tab set for alternate views of one tool-call payload.
//
// Native radio buttons own the selection. Rabbita therefore does not need to
// lift a transient viewing choice into the conversation model, while the
// browser still provides arrow-key navigation and a labelled control for each
// panel. All panels remain mounted; CSS lets only the selected one contribute
// height to the transcript.

///|
priv struct ToolCallTab {
  label : String
  body : @html.Html
}

///|
/// Render a radio-backed tab set. `key` is stable for the owning transcript
/// event, so a later render patches the same controls and preserves the tab
/// the reader selected. The first view is the useful default on first mount.
fn tool_call_tabs(key : String, tabs : Array[ToolCallTab]) -> @html.Html {
  let group = "tool-call-tabs-\{key}"
  let children : Array[@html.Html] = [
    @html.legend(class="visually-hidden", "Tool call details"),
  ]
  for index, tab in tabs {
    let id = "\{group}-\{index}"
    children.push(
      @html.input(
        input_type=Radio,
        name=group,
        id~,
        checked=index == 0,
        class="tool-call-tab-input",
      ),
    )
    children.push(@html.label(class="tool-call-tab-label", for_=id, tab.label))
  }
  children.push(
    @html.div(
      class="tool-call-tab-panels",
      [
        for tab in tabs => {
          @html.div(
            class="tool-call-tab-panel",
            attrs=@html.Attrs::build().role("region").aria_label(tab.label),
            [tab.body],
          )
        }
      ],
    ),
  )
  @html.fieldset(class="tool-call-tabs", children)
}

///|
/// Stable radio group identity for one recorded call. The call id takes
/// priority because one durable assistant event can emit several calls that
/// all share its sequence. Legacy calls without an id fall back to that
/// sequence; transient/test items use the empty id's stable hash last.
fn tool_call_tabs_key(call_id : String, sequence : Int?) -> String {
  if !call_id.is_empty() {
    return "call-\{call_id.hash()}"
  }
  match sequence {
    Some(sequence) => "sequence-\{sequence}"
    None => "call-\{call_id.hash()}"
  }
}

///|
/// Build the compact argument tabs shared by every ordinary tool call. A
/// custom card supplies the first semantic view for tools such as `mbtx` and
/// `edit`; other tools use the readable generic arguments view. Exact JSON is
/// a separate tab only when the first view is a derived reading rather than
/// the recording itself. The result deliberately does not join this tab set:
/// like the viz HTML renderer, the transcript renders it as its own row.
///
/// `None` when there is only one useful view: the existing labeled fallback is
/// clearer than a one-entry tab strip.
fn tool_arguments_tabbed_view(
  key : String,
  name : String,
  arguments : String?,
) -> @html.Html? {
  guard arguments is Some(arguments) else { return None }
  let trimmed = arguments.trim()
  guard !trimmed.is_empty() && trimmed != "{}" else { return None }
  let tabs : Array[ToolCallTab] = []
  match custom_card(name, arguments) {
    Some((label, card)) => {
      tabs.push({ label, body: card, })
      tabs.push({
        label: "Original JSON",
        body: original_json_content(arguments),
      })
    }
    None => {
      let content = json_arguments_content(arguments)
      tabs.push({ label: "Arguments", body: content.body, })
      if content.has_distinct_original {
        tabs.push({
          label: "Original JSON",
          body: original_json_content(arguments),
        })
      }
    }
  }
  if tabs.length() < 2 {
    return None
  }
  Some(tool_call_tabs(key, tabs))
}

///|
/// Result views for a tool call. A decoded MoonBit `read` gets a readable,
/// highlighted Output plus the exact numbered protocol in Original output;
/// every other result is already its own faithful display.
fn tool_output_tabs(
  name : String,
  arguments : String?,
  output : String,
) -> Array[ToolCallTab] {
  if output.is_blank() {
    return []
  }
  if name == "read" &&
    arguments is Some(arguments) &&
    @read_html.moonbit_output(arguments, output) is Some(rendered) {
    return [
      {
        label: "Output",
        body: @html.pre(class="tool-call-output", [rendered]),
      },
      {
        label: "Original output",
        body: @html.pre(class="tool-card-original-json", output),
      },
    ]
  }
  [
    {
      label: "Output",
      body: @html.pre(class="tool-call-output", truncate_output(output)),
    },
  ]
}
