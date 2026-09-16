// MoonBit documentation comments and item separators are anchored by the
// formatter's top-level `///|` marker. The reusable Viewer stays
// language-neutral, so OpenSeek supplies this small language adapter.

///|
priv struct MoonBitMarkdownCommentProvider {}

///|
impl @language.MarkdownCommentProvider for MoonBitMarkdownCommentProvider with fn provide_markdown_comments(
  _self,
  model,
) {
  moonbit_markdown_comments_in_snapshot(model.snapshot())
}

///|
fn install_moonbit_markdown_comment_provider() -> Unit {
  @languages.languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    MoonBitMarkdownCommentProvider::{ },
    foldable=true,
  )
  |> ignore
}

///|
/// Returns anchored MoonBit documentation and item-separator blocks. Every
/// `///|` marker becomes a Markdown horizontal rule; text after the marker is
/// the first documentation line, and consecutive `///` lines form the body.
fn moonbit_markdown_comments_in_snapshot(
  snapshot : @model.TextSnapshot,
) -> Array[@language.MarkdownCommentBlock] {
  let blocks : Array[@language.MarkdownCommentBlock] = []
  let line_count = snapshot.line_count()
  let mut line_number = 1
  while line_number <= line_count {
    guard moonbit_markdown_comment_anchor_content(
        snapshot.get_line_content(line_number),
      )
      is Some(anchor_content) else {
      line_number += 1
      continue
    }
    let start_line_number = line_number
    line_number += 1
    let contents : Array[String] = []
    if anchor_content != "" {
      contents.push(anchor_content)
    }
    while line_number <= line_count {
      match
        moonbit_markdown_comment_line_content(
          snapshot.get_line_content(line_number),
        ) {
        Some(content) => {
          contents.push(content)
          line_number += 1
        }
        None => break
      }
    }
    blocks.push({
      line_range: LineRange(start_line_number, line_number),
      markdown: if contents.is_empty() {
        "---"
      } else {
        (
          $|---
          $|
          $|\{contents.join("\n")}
        )
      },
    })
  }
  blocks
}

///|
/// Returns marker-line documentation, or `Some("")` for a bare separator.
fn moonbit_markdown_comment_anchor_content(line : String) -> String? {
  if !line.has_prefix("///|") {
    return None
  }
  let mut content_start = 4
  if content_start < line.length() && line[content_start].to_int() == 32 {
    content_start += 1
  }
  Some(line.unsafe_substring(start=content_start, end=line.length()))
}

///|
/// Strips exactly `///` and at most one following ASCII space. A following
/// `///|` starts a new block rather than extending the current one.
fn moonbit_markdown_comment_line_content(line : String) -> String? {
  if line.has_prefix("///|") || !line.has_prefix("///") {
    return None
  }
  let mut content_start = 3
  if content_start < line.length() && line[content_start].to_int() == 32 {
    content_start += 1
  }
  Some(line.unsafe_substring(start=content_start, end=line.length()))
}
