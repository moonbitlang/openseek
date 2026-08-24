// Generic JSON tool arguments rendered for people rather than for a parser.
//
// The session keeps the model's original payload, but an object is much easier
// to scan as labeled fields: string leaves can lose their JSON quotes and a
// multiline command or file body can become real preformatted text. Nested
// objects and arrays retain their shape through indentation. The original JSON
// remains immediately below the friendly view for debugging.

///|
/// A collapsed transcript row is still built, so compact but pathological JSON
/// must not turn into thousands of DOM nodes. Payload text is already clamped
/// by `truncate_output`; these limits bound the expansion after parsing it.
const MAX_FRIENDLY_ARGUMENT_NODES = 256

///|
const MAX_FRIENDLY_ARGUMENT_DEPTH = 6

///|
/// Render a generic argument payload. Non-object, malformed, truncated, or
/// unusually complex payloads retain the existing pretty-printed JSON/text
/// block. Ordinary objects become readable fields plus an Original JSON
/// disclosure.
fn json_arguments_view(arguments : String) -> @html.Html {
  let bounded = truncate_output(arguments)
  let parsed = @json.parse(bounded) catch {
    _ => return @html.pre(class="tool-call-arguments", bounded)
  }
  guard parsed is Object(fields) &&
    !fields.is_empty() &&
    friendly_argument_cost(parsed, 0) <= MAX_FRIENDLY_ARGUMENT_NODES else {
    return @html.pre(
      class="tool-call-arguments",
      truncate_output(parsed.stringify(indent=2)),
    )
  }
  @html.div(class="tool-call-arguments-friendly", [
    @html.div(
      class="tool-argument-fields",
      [
        for key, value in fields => argument_field(key, value)
      ],
    ),
    original_json_view(arguments),
  ])
}

///|
/// Approximate the number of elements the friendly renderer would construct,
/// stopping as soon as the shared node limit is exceeded. Deep containers are
/// treated as over-budget before recursing further.
fn friendly_argument_cost(value : Json, depth : Int) -> Int {
  match value {
    Object(fields) if !fields.is_empty() => {
      if depth >= MAX_FRIENDLY_ARGUMENT_DEPTH {
        return MAX_FRIENDLY_ARGUMENT_NODES + 1
      }
      let mut cost = 1
      for _, child in fields {
        cost += 1 + friendly_argument_cost(child, depth + 1)
        if cost > MAX_FRIENDLY_ARGUMENT_NODES {
          return cost
        }
      }
      cost
    }
    Array(items) if !items.is_empty() => {
      if depth >= MAX_FRIENDLY_ARGUMENT_DEPTH {
        return MAX_FRIENDLY_ARGUMENT_NODES + 1
      }
      let mut cost = 1
      for child in items {
        cost += 1 + friendly_argument_cost(child, depth + 1)
        if cost > MAX_FRIENDLY_ARGUMENT_NODES {
          return cost
        }
      }
      cost
    }
    _ => 1
  }
}

///|
fn argument_field(key : String, value : Json) -> @html.Html {
  @html.div(class="tool-argument-field", [
    @html.span(class="tool-argument-key", key),
    argument_value(value),
  ])
}

///|
/// Render a JSON value recursively. Strings are deliberately shown without
/// JSON quoting: a single-line path stays compact, while newlines in commands
/// and file bodies become actual line breaks. Every decoded string is clamped
/// again because its escaped JSON representation may have occupied one line.
fn argument_value(value : Json) -> @html.Html {
  match value {
    String(text) => {
      let text = truncate_output(text)
      if text.contains("\n") {
        @html.pre(class="tool-argument-value-block", text)
      } else {
        @html.span(class="tool-argument-value tool-argument-string", text)
      }
    }
    Object(fields) if !fields.is_empty() =>
      @html.div(
        class="tool-argument-object",
        [
          for key, child in fields => argument_field(key, child)
        ],
      )
    Array(items) if !items.is_empty() =>
      @html.div(
        class="tool-argument-array",
        [
          for child in items => {
            @html.div(class="tool-argument-item", [argument_value(child)])
          }
        ],
      )
    Object(_) => argument_scalar("{}", "container")
    Array(_) => argument_scalar("[]", "container")
    True => argument_scalar("true", "boolean")
    False => argument_scalar("false", "boolean")
    Null => argument_scalar("null", "null")
    Number(number, repr~) => {
      let text = match repr {
        Some(text) => text
        None => number.to_string()
      }
      argument_scalar(text, "number")
    }
  }
}

///|
fn argument_scalar(text : String, kind : String) -> @html.Html {
  @html.span(class="tool-argument-value tool-argument-\{kind}", text)
}
