// Recorded inputs and output share one invocation and one disclosure.

///|
fn tool_exchange_view(
  call : @transcript.ToolCall,
  sequence? : Int,
  subrun? : SubrunLink,
  wait_label? : String,
) -> @html.Html {
  let name = call.name
  let key = tool_call_tabs_key(call.call_id, sequence)
  let (status, is_error, brief, output) = match call.outcome {
    Pending(output~) =>
      (
        if output is Some(_) {
          "Output arriving"
        } else {
          "Awaiting result"
        },
        false,
        None,
        output,
      )
    Done(is_error~, brief~, content~) =>
      (
        if is_error {
          "Tool failed"
        } else {
          "Result available"
        },
        is_error,
        brief,
        Some(content),
      )
  }
  let label = if wait_label is Some(label) {
    label
  } else if pending_job_wait_label(call) is Some(label) {
    label
  } else if name == "read" &&
    call.arguments is Some(arguments) &&
    card_fields(arguments) is Some(fields) &&
    fields.get("path") is Some(String(path)) {
    "Read · " + path
  } else {
    let label = match brief {
      Some(text) if !text.is_blank() => text
      _ => name
    }
    if name == "mbtx" &&
      call.arguments is Some(arguments) &&
      card_fields(arguments) is Some(fields) &&
      fields.get("description") is Some(String(description)) &&
      !description.is_blank() {
      label + " · " + description
    } else {
      label
    }
  }
  // Bound the actual focus label, not only its visual paint. The complete
  // caption remains readable in the body when it exceeds this compact label.
  let cut = String::from_iter(label.iter().take(120))
  let caption = if cut.length() < label.length() { cut + "…" } else { cut }
  let body : Array[@html.Html] = []
  if call.arguments is Some(arguments) {
    // A `plan` call shows the checklist it recorded rather than its JSON, in
    // every state where that checklist is what the model asked for. A pending
    // call qualifies: the card is a record of the call, and the missing Output
    // section already marks it unfinished. A rejected one does not — the
    // malformed arguments are what the reader needs, and dressing them up as a
    // checklist would report a plan that never took effect.
    if @plan.classify(call) is Some(Applied(steps) | Pending(steps)) {
      body.push(@html.div(class="tool-call-section", [@plan.card(steps)]))
    } else if tool_arguments_tabbed_view(
        tool_call_tabs_key(call.call_id, sequence),
        name,
        Some(arguments),
      )
      is Some(tabs) {
      body.push(@html.div(class="tool-call-section", [tabs]))
    } else if custom_card(name, arguments) is Some((label, card)) {
      // Some tools' arguments have a shape JSON hides, such as an `edit` split
      // across two blobs whose difference is the whole point. Those get a card.
      // A payload the card cannot read falls through to the generic rendering
      // below, so nothing is ever shown as a change that is not one.
      body.push(
        @html.div(class="tool-call-section", [
          @html.div(class="tool-call-section-label", label),
          card,
        ]),
      )
    } else {
      let trimmed = arguments.trim()
      if !trimmed.is_empty() && trimmed != "{}" {
        body.push(
          @html.div(class="tool-call-section", [
            @html.div(class="tool-call-section-label", "Arguments"),
            json_arguments_content(arguments).body,
          ]),
        )
      }
    }
  }
  if body.is_empty() {
    body.push(
      @html.div(class="tool-call-section", [
        @html.div(class="tool-call-section-label", "Arguments"),
        @html.div(
          class="tool-empty",
          if call.arguments is None {
            "No arguments recorded."
          } else {
            "No arguments."
          },
        ),
      ]),
    )
  }
  if caption != label {
    body.insert(0, @html.div(class="tool-caption", truncate_output(label)))
  }
  let inputs = @html.div(class="tool-input", body)
  let output_sections = tool_output_sections(
    name,
    call.arguments,
    brief,
    output,
    key,
    subrun?,
  )
  if output_sections.is_empty() {
    output_sections.push(
      @html.div(class="tool-call-section", [
        @html.div(class="tool-call-section-label", "Output"),
        @html.div(
          class="tool-empty",
          if output is None {
            "Waiting for a result…"
          } else {
            "No output returned."
          },
        ),
      ]),
    )
  }
  let status_icon = match call.outcome {
    Pending(..) => @icons.icon_circle
    Done(is_error=true, ..) => @icons.icon_error
    Done(..) => @icons.icon_check
  }
  @html.details(
    class="tool-call" +
      (if is_error { " error" } else { "" }) +
      failure_stage_class(name, brief, is_error, call.arguments),
    [
      @html.summary(
        class="work-toggle tool-toggle",
        attrs=@html.Attrs::build().aria_label(caption + " — " + status),
        [
          @html.span(class="work-chevron", @icons.icon_chevron_down()),
          @html.span(class="tool-call-text", caption),
          @plan.fold_progress(call),
          match
            failure_marker(
              name,
              brief,
              is_error,
              call.arguments,
              brief_shown=brief is Some(text) && caption.contains(text),
            ) {
            Some(marker) => marker
            None => @html.nothing
          },
          @html.span(
            class="tool-status",
            attrs=@html.Attrs::build()
              .role("img")
              .aria_label(status)
              .title(status),
            @icons.icon(status_icon),
          ),
        ],
      ),
      @html.div(class="tool-body", {
        "input": inputs,
        "output": @html.div(class="tool-output", output_sections),
      }),
    ],
  )
}
