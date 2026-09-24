// Block layout adapted from moonbit-community/cmark@0.4.5,
// src/cmark_html/html.mbt, to emit AST identities when opening block tags.
// Copyright 2024 International Digital Economy Academy
// Licensed under the Apache License, Version 2.0 (see editor/LICENSE).
//
// Original cmarkit code:
// Copyright (c) 2020 The cmarkit programmers
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

///|
/// The document renderer owns block tags so their source identity is emitted
/// alongside the tag. cmark still owns inline escaping, links, raw-HTML policy,
/// footnote state, and document traversal. List items and table cells fall back
/// to their containing marked block when they have no paragraph element.
fn markdown_source_renderer() -> @cmark_renderer.Renderer {
  let heading_ids : Set[String] = Set([])
  let default_renderer = @cmark_html.renderer(safe=true)
  @cmark_renderer.Renderer::new(block=fn(ctx, block) raise {
    let node_id = block.meta().id
    let attrs = markdown_node_attribute(node_id)
    match block {
      BlockQuote(node) => {
        ctx.string("<blockquote\{attrs}>\n")
        ctx.block(node.v.block)
        ctx.string("</blockquote>\n")
      }
      Paragraph(node) => {
        ctx.string("<p\{attrs}>")
        ctx.inline(node.v.inline)
        ctx.string("</p>\n")
      }
      Heading(node) => markdown_source_heading(ctx, node.v, attrs, heading_ids)
      List(node) => markdown_source_list(ctx, node.v, attrs)
      ExtTable(node) => markdown_source_table(ctx, node.v, attrs)
      CodeBlock(node) => {
        ctx.string("<pre\{attrs}><code")
        let lang = node.v.info_string
          .map(info => info.v)
          .bind(@cmark.CodeBlock::language_of_info_string)
        if lang is Some((lang, _)) {
          ctx.string(" class=\"language-\{@common.escape_html(lang)}\"")
        }
        ctx.string(">")
        for line in node.v.code {
          ctx.string(@common.escape_html(line.v))
          ctx.string("\n")
        }
        ctx.string("</code></pre>\n")
      }
      ExtMathBlock(_) => {
        ctx.string(
          "<div class=\"moonbit-viewer-markdown-source-block\"\{attrs}>",
        )
        let _ = (default_renderer.block)(ctx, block)
        ctx.string("</div>")
      }
      ThematicBreak(_) => ctx.string("<hr\{attrs}>\n")
      _ => return false
    }
    true
  })
}

///|
fn markdown_node_attribute(node_id : Int) -> String {
  " data-markdown-node-id=\"\{node_id}\""
}

///|
/// A renderer override may emit any number of roots. One owned wrapper keeps
/// all of them associated with the code block that produced them.
fn markdown_write_code_override(
  ctx : @cmark_renderer.Context,
  node_id : Int,
  html : String,
  source_mapping~ : Bool,
) -> Unit {
  if source_mapping {
    ctx.string(
      "<div class=\"moonbit-viewer-markdown-source-block\"\{markdown_node_attribute(node_id)}>",
    )
    ctx.string(html)
    ctx.string("</div>")
  } else {
    ctx.string(html)
  }
}

///|
fn markdown_source_heading(
  c : @cmark_renderer.Context,
  h : @cmark.BlockHeading,
  attrs : String,
  ids : Set[String],
) -> Unit raise {
  c.string("<h\{h.level}\{attrs}")
  match h.id {
    None => c.string(">")
    Some(Auto(id) | Id(id)) => {
      let id = for counter = 0 {
        let candidate = if counter == 0 { id } else { "\{id}-\{counter}" }
        if ids.contains(candidate) {
          continue counter + 1
        }
        ids.add(candidate)
        break candidate
      }
      let id = @common.escape_html(id)
      c.string(
        " id=\"\{id}\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#\{id}\"></a>",
      )
    }
  }
  c.inline(h.inline)
  c.string("</h\{h.level}>\n")
}

///|
fn markdown_source_item_block(
  tight~ : Bool,
  c : @cmark_renderer.Context,
  b : @cmark.Block,
) -> Unit raise {
  match (b, tight) {
    (BlankLine(_), _) => ()
    (Paragraph({ v, .. }), true) => c.inline(v.inline)
    (Blocks({ v, .. }), _) =>
      for add_nl = true, bs = v.to_array()[:] {
        match (bs, tight) {
          ([BlankLine(_), .. bs], _) => continue add_nl, bs
          ([Paragraph({ v, .. }), .. bs], true) => {
            c.inline(v.inline)
            continue true, bs
          }
          ([b, .. bs], _) => {
            if add_nl {
              c.b.write_char('\n')
            }
            c.block(b)
            continue false, bs
          }
          _ => break
        }
      }
    _ => {
      c.b.write_char('\n')
      c.block(b)
    }
  }
}

///|
fn markdown_source_list_item(
  tight~ : Bool,
  c : @cmark_renderer.Context,
  i : @cmark.Node[@cmark.ListItem],
) -> Unit raise {
  c.b.write_string("<li>")
  guard i.v.ext_task_marker is Some(mark) else {
    markdown_source_item_block(tight~, c, i.v.block)
    c.b.write_string("</li>\n")
    return
  }
  let close = match @cmark.ListTaskStatus::from_marker(mark.v) {
    Unchecked => {
      c.b.write_string(
        "<div class=\"task\"><input type=\"checkbox\" disabled><div>",
      )
      "</div></div></li>\n"
    }
    Checked | Other(_) => {
      c.b.write_string(
        "<div class=\"task\"><input type=\"checkbox\" disabled checked><div>",
      )
      "</div></div></li>\n"
    }
    Cancelled => {
      c.b.write_string(
        "<div class=\"task\"><input type=\"checkbox\" disabled><del>",
      )
      "</del></div></li>\n"
    }
  }
  markdown_source_item_block(tight~, c, i.v.block)
  c.b.write_string(close)
}

///|
fn markdown_source_list(
  c : @cmark_renderer.Context,
  l : @cmark.BlockList,
  attrs : String,
) -> Unit raise {
  let tight = l.tight
  match l.ty {
    Unordered(_) => {
      c.b.write_string("<ul\{attrs}>\n")
      for i in l.items {
        markdown_source_list_item(tight~, c, i)
      }
      c.b.write_string("</ul>\n")
    }
    Ordered(start, _) => {
      c.b.write_string("<ol\{attrs}")
      if start == 1 {
        c.b.write_string(">\n")
      } else {
        c.b.write_string(" start=\"")
        c.b.write_object(start)
        c.b.write_string("\">\n")
      }
      for i in l.items {
        markdown_source_list_item(tight~, c, i)
      }
      c.b.write_string("</ol>\n")
    }
  }
}

///|
fn markdown_source_table(
  c : @cmark_renderer.Context,
  t : @cmark.Table,
  attrs : String,
) -> Unit raise {
  fn start(c : @cmark_renderer.Context, align : @cmark.TableAlign?, tag) {
    c.b.write_char('<')
    c.b.write_string(tag)
    match align {
      None => c.b.write_char('>')
      Some(Left) => c.b.write_string(" class=\"left\">")
      Some(Center) => c.b.write_string(" class=\"center\">")
      Some(Right) => c.b.write_string(" class=\"right\">")
    }
  }

  fn close(c : @cmark_renderer.Context, tag) {
    c.b.write_string("</")
    c.b.write_string(tag)
    c.b.write_string(">\n")
  }

  fn cols(
    c : @cmark_renderer.Context,
    tag,
    align : ArrayView[@cmark.Node[@cmark.TableSep]],
    count,
    cs : ArrayView[(_, _)],
  ) raise {
    match (align, cs) {
      ([{ v, .. }, .. align], [(col, _), .. cs]) => {
        start(c, v.0.0, tag)
        c.inline(col)
        close(c, tag)
        cols(c, tag, align, count - 1, cs)
      }
      ([{ v, .. }, .. align], []) => {
        start(c, v.0.0, tag)
        close(c, tag)
        cols(c, tag, align, count - 1, [][:])
      }
      ([], [(col, _), .. cs]) => {
        start(c, None, tag)
        c.inline(col)
        close(c, tag)
        cols(c, tag, [][:], count - 1, cs)
      }
      ([], []) =>
        for _ in 0..<count {
          start(c, None, tag)
          close(c, tag)
        }
    }
  }

  fn row(c : @cmark_renderer.Context, tag, align, count, cs) raise {
    c.b.write_string("<tr>\n")
    cols(c, tag, align, count, cs)
    c.b.write_string("</tr>\n")
  }

  fn header(c : @cmark_renderer.Context, count, align, cols) raise {
    row(c, "th", align, count, cols)
  }

  fn data(c : @cmark_renderer.Context, count, align, cols) raise {
    row(c, "td", align, count, cols)
  }

  fn rows(
    c : @cmark_renderer.Context,
    col_count,
    align : ArrayView[_],
    rs : ArrayView[(@cmark.Node[@cmark.TableRow], _)],
  ) raise {
    match rs {
      [({ v: Header(cols), .. }, _), .. rs] => {
        let (align, rs) = match rs {
          [({ v: Sep(align), .. }, _), .. rs] => (align.to_array()[:], rs)
          _ => (align, rs)
        }
        header(c, col_count, align, cols.to_array()[:])
        rows(c, col_count, align, rs)
      }
      [({ v: Data(cols), .. }, _), .. rs] => {
        data(c, col_count, align, cols.to_array()[:])
        rows(c, col_count, align, rs)
      }
      [({ v: Sep(align), .. }, _), .. rs] =>
        rows(c, col_count, align.to_array()[:], rs)
      [] => ()
    }
  }

  c.b.write_string("<div role=\"region\"\{attrs}><table>\n")
  rows(c, t.col_count, [][:], t.rows.to_array()[:])
  c.b.write_string("</table></div>")
}
