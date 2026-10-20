///|
/// Presentation state for one live assistant message. The transcript owns it
/// for the lifetime of its keyed render branch; Markdown source stays intact.
pub struct StreamingMarkdown {
  mut source : String
  ends : Array[Int]
}

///|
pub fn StreamingMarkdown::new() -> StreamingMarkdown {
  { source: "", ends: [], }
}

///|
priv struct StreamingFragments {
  source : String
  ends : Array[Int]
  fresh_from : Int
}

///|
/// Reparse the accumulated source while retaining the boundaries of received
/// fragments. CSS owns the opacity transition, including its duration.
pub fn StreamingMarkdown::nodes(
  self : StreamingMarkdown,
  locale~ : @i18n.Locale = English,
  source : String,
  open_file? : (String) -> @cmd.Cmd,
) -> Array[@html.Html] {
  let fresh_from = if source.has_prefix(self.source) {
    self.source.length()
  } else {
    // A retry or a new provider step replaces the provisional response.
    self.ends.clear()
    0
  }
  if source != self.source {
    self.ends.push(source.length())
  }
  self.source = source
  render_markdown(
    locale~,
    source,
    open_file?,
    streaming=Some({ source, ends: self.ends, fresh_from, }),
  )
}

///|
fn stream_fragment(text : String, fresh : Bool) -> @html.Html {
  @html.span(
    class=if fresh { "stream-fragment fresh" } else { "stream-fragment" },
    text,
  )
}

///|
/// cmark can decode escapes and character references. Only split text by
/// source offsets when it still matches the source; transformed old text is
/// kept visible instead of being mistaken for newly received content.
fn MarkdownRender::text_offset(
  self : MarkdownRender,
  node : @cmark.Node[String],
) -> Int? {
  guard self.streaming is Some(stream) else { return None }
  let first = node.meta.loc.first_ccode
  let end = node.meta.loc.last_ccode + 1
  guard first >= 0 && end >= first && end <= stream.source.length() else {
    return None
  }
  if stream.source.view(start_offset=first, end_offset=end) == node.v.view() {
    Some(first)
  } else {
    None
  }
}

///|
fn MarkdownRender::fresh_text(
  self : MarkdownRender,
  node : @cmark.Node[String],
) -> Bool {
  self.streaming.map_or(false, stream => {
    node.meta.loc.first_ccode >= stream.fresh_from
  })
}

///|
fn MarkdownRender::text_nodes(
  self : MarkdownRender,
  text : String,
  first? : Int,
  fresh~ : Bool = false,
) -> Array[@html.Html] {
  guard self.streaming is Some(stream) else { return [@html.text(text)] }
  guard first is Some(first) else {
    return if fresh { [stream_fragment(text, true)] } else { [@html.text(text)] }
  }
  let out : Array[@html.Html] = []
  let mut boundary = match stream.ends.binary_search(first) {
    Ok(index) => index + 1
    Err(index) => index
  }
  let mut start = 0
  // Iterate scalar boundaries rather than slicing at an arbitrary incoming
  // UTF-16 offset, so a fragment boundary cannot split a surrogate pair.
  for offset, _ in text {
    if boundary < stream.ends.length() &&
      stream.ends[boundary] <= first + offset {
      if offset > start {
        out.push(
          stream_fragment(
            text.view(start_offset=start, end_offset=offset).to_owned(),
            first + start >= stream.fresh_from,
          ),
        )
      }
      start = offset
      while boundary < stream.ends.length() &&
        stream.ends[boundary] <= first + offset {
        boundary += 1
      }
    }
  }
  if start < text.length() {
    out.push(
      stream_fragment(
        text.view(start_offset=start).to_owned(),
        first + start >= stream.fresh_from,
      ),
    )
  }
  out
}
