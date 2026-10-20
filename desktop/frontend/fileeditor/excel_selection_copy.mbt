///|
pub(all) enum ExcelCopyFormat {
  Tsv
  Markdown
} derive(Eq)

///|
pub extend ExcelCopyFormat with Eq::{equal, not_equal}

///|
/// Keep the complete cell contents separately from the bounded Agent preview.
/// Coordinates retain empty rows/columns and the covered area of merged cells.
pub struct ExcelSelectionTable {
  first_row : Int32
  last_row : Int32
  first_column : Int32
  last_column : Int32
  cells : Map[(Int32, Int32), String]
} derive(Eq)

///|
pub extend ExcelSelectionTable with Eq::{equal, not_equal}

///|
pub(all) enum ExcelCopyStatus {
  Copying
  Copied
  Failed
} derive(Eq)

///|
pub extend ExcelCopyStatus with Eq::{equal, not_equal}

///|
pub(all) struct ExcelCopyFeedback {
  preview : OfficeSelectionPreview
  generation : Int32
  format : ExcelCopyFormat
  status : ExcelCopyStatus
} derive(Eq)

///|
pub extend ExcelCopyFeedback with Eq::{equal, not_equal}

///|
/// Clipboard selection survives closing the optional Agent feedback draft.
/// Document ownership and revision still fence every copy and completion.
fn State::pending_excel_selection(
  self : State,
  ctx : Ctx,
) -> OfficeSelectionPreview? {
  self.excel_copy_selection.filter(preview => {
    preview.excel_table is Some(_) &&
    self.accepts_office_callback(
      ctx,
      @interop.Host(preview.owner),
      preview.epoch,
      preview.path,
      preview.sig,
    )
  })
}

///|
fn excel_copy_cell(address : String) -> (Int32, Int32)? {
  guard address =~ re"^[A-Z]{1,3}[1-9][0-9]*$" else { return None }
  let mut column = 0
  let mut offset = 0
  for ch in address {
    if ch < 'A' || ch > 'Z' {
      break
    }
    column = column * 26 + ch.to_int() - 64
    offset += 1
  }
  let row = @string.parse_int(address[offset:]) catch { _ => return None }
  if column <= 16384 && row <= 1048576 {
    Some((row, column))
  } else {
    None
  }
}

///|
fn excel_selection_table(raw : String) -> ExcelSelectionTable? {
  let value = @json.parse(raw) catch { _ => return None }
  guard value
    is {
      "schema": String("office.selection.v1"),
      "format": String("xlsx"),
      "kind": String("excel"),
      "range": String(range_),
      "cells": Array(cells),
      ..
    } else {
    return None
  }
  let (start, end) = match range_.split_once(":") {
    Some((start, end)) => (start.to_owned(), end.to_owned())
    None => (range_, range_)
  }
  guard excel_copy_cell(start) is Some((first_row, first_column)) &&
    excel_copy_cell(end) is Some((last_row, last_column)) &&
    first_row <= last_row &&
    first_column <= last_column &&
    !cells.is_empty() else {
    return None
  }
  let values : Map[(Int32, Int32), String] = Map([])
  for cell in cells {
    guard cell is { "address": String(address), "text": String(text), .. } &&
      excel_copy_cell(address) is Some((row, column)) &&
      row <= last_row &&
      column <= last_column else {
      return None
    }
    // A merge intersecting the selection can start above or left of it.
    // Flatten its text into the first selected slot; covered slots stay empty.
    let position = (row.max(first_row), column.max(first_column))
    guard !values.contains(position) else { return None }
    values[position] = text
  }
  Some({ first_row, last_row, first_column, last_column, cells: values, })
}

///|
fn excel_tsv_cell(text : String) -> String {
  if text.contains_any(chars="\t\r\n\"") {
    "\"" + text.replace_all(old="\"", new="\"\"") + "\""
  } else {
    text
  }
}

///|
fn excel_markdown_cell(text : String) -> String {
  let out = StringBuilder()
  for
    ch in text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n") {
    match ch {
      '\n' => out.write_string("<br>")
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '\\' | '|' | '`' | '*' | '_' | '[' | ']' | '~' | '$' => {
        out.write_char('\\')
        out.write_char(ch)
      }
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Bound clipboard expansion, including a merge covering a huge worksheet.
/// The normal preview window (1000 × 256) fits without truncating its contents.
fn ExcelSelectionTable::text(
  self : ExcelSelectionTable,
  format : ExcelCopyFormat,
) -> String? {
  let rows = self.last_row - self.first_row + 1
  let columns = self.last_column - self.first_column + 1
  guard rows.to_int64() * columns.to_int64() <= 1000000L else { return None }
  let out = StringBuilder()
  for row in self.first_row..<=self.last_row {
    if row > self.first_row {
      out.write_string(if format == Tsv { "\r\n" } else { "\n" })
    }
    if format == Markdown {
      out.write_string("| ")
    }
    for column in self.first_column..<=self.last_column {
      if column > self.first_column {
        out.write_string(if format == Tsv { "\t" } else { " | " })
      }
      let text = self.cells.get_or_default((row, column), "")
      out.write_string(
        if format == Tsv {
          excel_tsv_cell(text)
        } else {
          excel_markdown_cell(text)
        },
      )
    }
    if format == Markdown {
      out.write_string(" |")
      if row == self.first_row {
        out.write_string("\n|")
        for _ in 0..<columns {
          out.write_string(" --- |")
        }
      }
    }
  }
  Some(out.to_string())
}

///|
fn State::copy_excel_selection(
  self : State,
  ctx : Ctx,
  emit : @cmd.Emit[Msg],
  preview : OfficeSelectionPreview,
  format : ExcelCopyFormat,
) -> (@cmd.Cmd, State) {
  guard self.pending_excel_selection(ctx) == Some(preview) &&
    preview.excel_table is Some(table) else {
    return (@cmd.none, self)
  }
  guard table.text(format) is Some(text) else {
    return (
      @cmd.none,
      { ..self, error: Some(ui(ctx.locale, ExcelCopyTooLarge)), },
    )
  }
  let generation = self.excel_copy_generation + 1
  (
    @clipboard.copy(
      Text(text),
      copied=emit(ExcelSelectionCopyFinished(preview, generation, true)),
      failed=_ => emit(ExcelSelectionCopyFinished(preview, generation, false)),
    ),
    {
      ..self,
      excel_copy_generation: generation,
      excel_copy_feedback: Some({
        preview,
        generation,
        format,
        status: Copying,
      }),
    },
  )
}

///|
fn excel_copy_controls(
  locale~ : @i18n.Locale,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard state.pending_excel_selection(ctx) is Some(preview) &&
    preview.excel_table is Some(_) else {
    return @html.nothing
  }
  let feedback = state.excel_copy_feedback.filter(value => {
    value.preview == preview
  })
  let copying = feedback.map(value => value.status == Copying).unwrap_or(false)
  @html.div(
    class="excel-copy-controls",
    attrs=@html.Attrs::build().on_keydown(event => {
      if event
        .to_keyboard_event()
        .map(key => key.key() == "Escape")
        .unwrap_or(false) {
        dispatch(ExcelSelectionCleared(preview))
      } else {
        @cmd.none
      }
    }),
    [
      @html.span(
        class="excel-copy-range",
        preview.summary.location.unwrap_or(""),
      ),
      @html.button(
        type_="button",
        class="office-viewer-control excel-copy-table",
        title=ui(locale, ExcelCopyTableHint),
        disabled=copying,
        attrs=@html.Attrs::build().aria_label(ui(locale, ExcelCopyTable)),
        on_click=dispatch(ExcelSelectionCopyRequested(preview, Tsv)),
        ui(locale, ExcelCopyTable),
      ),
      @html.button(
        type_="button",
        class="office-viewer-control excel-copy-markdown",
        title=ui(locale, ExcelCopyMarkdownHint),
        disabled=copying,
        attrs=@html.Attrs::build().aria_label(ui(locale, ExcelCopyMarkdown)),
        on_click=dispatch(ExcelSelectionCopyRequested(preview, Markdown)),
        "Markdown",
      ),
      @html.span(
        class="excel-copy-feedback",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        match feedback.map(value => value.status) {
          Some(Copied) => ui(locale, ExcelCopied)
          Some(Failed) => ui(locale, ExcelCopyFailed)
          _ => ""
        },
      ),
    ],
  )
}
