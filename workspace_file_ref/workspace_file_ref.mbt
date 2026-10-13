///|
/// The fence language emitted by a model when it wants to reference one
/// workspace item without embedding its contents in the conversation.
pub const FenceLanguage : String = "openseek-file"

///|
/// A coarse presentation category derived from the referenced item's final
/// extension. The category is a rendering hint; opening still goes through
/// the host's ordinary path resolver.
pub enum FileKind {
  Spreadsheet
  Document
  Presentation
  Image
  Pdf
  Archive
  Code
  Text
  Generic
} derive(Eq, Debug)

///|
pub extend FileKind with Eq::{equal, not_equal}

///|
pub extend FileKind with Debug::{to_repr}

///|
/// A validated workspace-relative file reference extracted from a fenced
/// block. The path is kept exactly as authored after outer whitespace is
/// removed; it is never resolved or read by this package.
pub struct WorkspaceFileRef {
  path : String
  name : String
  extension : String?
  kind : FileKind
} derive(Eq, Debug)

///|
pub extend WorkspaceFileRef with Eq::{equal, not_equal}

///|
pub extend WorkspaceFileRef with Debug::{to_repr}

///|
/// A Markdown source split into ordinary text and recognized workspace-file
/// fences. Invalid or unfinished fences remain ordinary text so a renderer
/// never loses model output while it is streaming.
pub enum MarkdownPart {
  Text(String)
  File(WorkspaceFileRef)
} derive(Eq, Debug)

///|
pub extend MarkdownPart with Eq::{equal, not_equal}

///|
pub extend MarkdownPart with Debug::{to_repr}

///|
/// Return the 16x16 filled SVG path used for a file-kind icon. The renderers
/// own the SVG element so the pure package stays independent of Rabbita while
/// both desktop and exported views share the same geometry.
pub fn file_icon_path(kind : FileKind) -> String {
  match kind {
    Spreadsheet =>
      "M1 1H15V2H1V1ZM1 14H15V15H1V14ZM1 1H2V15H1V1ZM14 1H15V15H14V1ZM5 1H6V15H5V1ZM10 1H11V15H10V1ZM1 5H15V6H1V5ZM1 10H15V11H1V10Z"
    Document | Pdf | Text | Generic =>
      "M5 1C3.89543 1 3 1.89543 3 3V13C3 14.1046 3.89543 15 5 15H11C12.1046 15 13 14.1046 13 13V5.41421C13 5.01639 12.842 4.63486 12.5607 4.35355L9.64645 1.43934C9.36514 1.15804 8.98379 1 8.58579 1H5ZM4 3C4 2.44772 4.44772 2 5 2H8V4.5C8 5.32843 8.67157 6 9.5 6H12V13C12 13.5523 11.5523 14 11 14H5C4.44772 14 4 13.5523 4 13V3ZM11.7929 5H9.5C9.22386 5 9 4.77614 9 4.5V2.20711L11.7929 5Z"
    Presentation =>
      "M1 1H15V2H1V1ZM1 9H15V10H1V9ZM1 1H2V10H1V1ZM14 1H15V10H14V1ZM7 10H9V13H7V10ZM4 13H12V15H4V13Z"
    Image =>
      "M6 1C4.89543 1 4 1.89543 4 3V6H5V3C5 2.44772 5.44772 2 6 2H9V4.5C9 5.32843 9.67157 6 10.5 6H13V13C13 13.5523 12.5523 14 12 14H10.9646C10.9141 14.3531 10.8109 14.6891 10.6632 15H12C13.1046 15 14 14.1046 14 13V5.41421C14 5.01639 13.842 4.63486 13.5607 4.35355L10.6464 1.43934C10.3651 1.15804 9.98361 1 9.58579 1H6ZM12.7929 5H10.5C10.2239 5 10 4.77614 10 4.5V2.20711L12.7929 5ZM1 9.5C1 8.11929 2.11929 7 3.5 7H7.5C8.88071 7 10 8.11929 10 9.5V13.5C10 14.0095 9.84756 14.4835 9.5858 14.8787L6.56066 11.8536C5.97487 11.2678 5.02513 11.2678 4.43934 11.8536L1.4142 14.8787C1.15244 14.4835 1 14.0095 1 13.5V9.5ZM8 9.75C8 9.33579 7.66421 9 7.25 9C6.83579 9 6.5 9.33579 6.5 9.75C6.5 10.1642 6.83579 10.5 7.25 10.5C7.66421 10.5 8 10.1642 8 9.75ZM2.12131 15.5858C2.51652 15.8476 2.99046 16 3.5 16H7.5C8.00954 16 8.48348 15.8476 8.87869 15.5858L5.85355 12.5607C5.65829 12.3654 5.34171 12.3654 5.14645 12.5607L2.12131 15.5858Z"
    Archive =>
      "M6.5 8C6.22386 8 6 8.22386 6 8.5C6 8.77614 6.22386 9 6.5 9H9.5C9.77614 9 10 8.77614 10 8.5C10 8.22386 9.77614 8 9.5 8H6.5ZM1 3.5C1 2.67157 1.67157 2 2.5 2H13.5C14.3284 2 15 2.67157 15 3.5V4.5C15 5.15311 14.5826 5.70873 14 5.91465V11.5C14 12.8807 12.8807 14 11.5 14H4.5C3.11929 14 2 12.8807 2 11.5V5.91465C1.4174 5.70873 1 5.15311 1 4.5V3.5ZM2.5 3C2.22386 3 2 3.22386 2 3.5V4.5C2 4.77614 2.22386 5 2.5 5H13.5C13.7761 5 14 4.77614 14 4.5V3.5C14 3.22386 13.7761 3 13.5 3H2.5ZM3 6V11.5C3 12.3284 3.67157 13 4.5 13H11.5C12.3284 13 13 12.3284 13 11.5V6H3Z"
    Code =>
      "M5 4L1 8L5 12L6.41421 10.5858L3.82843 8L6.41421 5.41421L5 4ZM11 4L9.58579 5.41421L12.1716 8L9.58579 10.5858L11 12L15 8L11 4ZM8.5 2L7.5 2L7.5 14L8.5 14L8.5 2Z"
  }
}

///|
/// Decode one already-parsed fenced code block.
///
/// `closed` must be true for a renderer to replace the source with a card.
/// The path grammar intentionally accepts only one non-empty line and rejects
/// absolute paths and parent traversal, keeping exported references portable
/// and preventing a model response from naming an arbitrary local file.
pub fn parse(
  language : String,
  source : String,
  closed~ : Bool,
) -> WorkspaceFileRef? {
  guard closed && language == FenceLanguage else { return None }
  let path = source.trim().to_owned()
  guard !path.is_empty() && !path.contains("\n") && !path.contains("\r") else {
    return None
  }
  guard !path.contains_char('\u{0}') && !path.contains_char('\t') else {
    return None
  }
  guard !is_absolute_or_uri(path) else { return None }
  let normalized = path.replace_all(old="\\", new="/")
  guard !normalized.has_suffix("/") else { return None }
  let components = normalized.split("/").collect()
  guard !components.is_empty() && components.any(part => !part.is_empty()) else {
    return None
  }
  for component in components {
    guard component != ".." else { return None }
  }
  let name = match normalized.rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => normalized
  }
  guard !name.is_empty() && name != "." && name != ".." else { return None }
  let extension = extension_of(name)
  let kind = file_kind(name)
  { path, name, extension, kind, } |> Some
}

///|
/// Split assistant text while retaining every non-file line verbatim. This is
/// deliberately a small fence scanner for the export viewer: the desktop
/// renderer already has the full cmark AST, while the viewer only needs to
/// project this one additional block type without changing its existing plain
/// text presentation for other Markdown.
pub fn markdown_parts(source : String) -> Array[MarkdownPart] {
  let lines = source.split("\n").map(line => line.to_owned()).collect()
  let parts : Array[MarkdownPart] = []
  let mut pending : Array[String] = []
  let mut index = 0
  while index < lines.length() {
    match opening_fence(lines[index]) {
      Some(fence_length) =>
        match closing_fence(lines, index + 1, fence_length) {
          Some(close) => {
            let body = join_lines(lines, index + 1, close)
            match parse(FenceLanguage, body, closed=true) {
              Some(reference) => {
                flush_text(parts, pending)
                parts.push(File(reference))
                pending = []
                index = close + 1
                continue
              }
              None => ()
            }
          }
          None => ()
        }
      None => ()
    }
    pending.push(lines[index])
    index += 1
  }
  flush_text(parts, pending)
  parts
}

///|
fn flush_text(parts : Array[MarkdownPart], pending : Array[String]) -> Unit {
  guard !pending.is_empty() else { return }
  let text = pending.join("\n")
  guard !text.is_empty() else { return }
  parts.push(Text(text))
}

///|
fn join_lines(lines : Array[String], start : Int32, end : Int32) -> String {
  let result : Array[String] = []
  for index = start; index < end; index = index + 1 {
    result.push(lines[index])
  }
  result.join("\n")
}

///|
/// Return the opening backtick count for an exact `openseek-file` fence.
fn opening_fence(line : String) -> Int32? {
  let candidate = line.trim_start()
  guard candidate.length() >= FenceLanguage.length() + 3 else { return None }
  guard candidate.has_prefix("```") else { return None }
  let mut count = 0
  while count < candidate.length() && candidate[count] == '`' {
    count += 1
  }
  guard count >= 3 else { return None }
  let info = candidate[count:].trim()
  guard info == FenceLanguage else { return None }
  Some(count)
}

///|
fn closing_fence(
  lines : Array[String],
  start : Int32,
  minimum : Int32,
) -> Int32? {
  for index = start; index < lines.length(); index = index + 1 {
    let candidate = lines[index].trim()
    if candidate.length() >= minimum && candidate.has_prefix("```") {
      let mut count = 0
      while count < candidate.length() && candidate[count] == '`' {
        count += 1
      }
      if count >= minimum && candidate[count:].trim().is_empty() {
        return Some(index)
      }
    }
  }
  None
}

///|
fn is_absolute_or_uri(path : String) -> Bool {
  let lower = path.to_lower()
  path.has_prefix("/") ||
  path.has_prefix("\\") ||
  path == "~" ||
  path.has_prefix("~/") ||
  path.has_prefix("~\\") ||
  lower.has_prefix("file:") ||
  (path.length() >= 2 && path[1] == ':')
}

///|
fn extension_of(name : String) -> String? {
  match name.rev_split_once(".") {
    Some((stem, extension)) if !stem.is_empty() && !extension.is_empty() =>
      Some(extension.to_owned().to_lower())
    _ => None
  }
}

///|

///|
/// Return the icon category for a workspace entry name. This is a rendering
/// hint shared by the transcript cards, exported viewer, and file tree; it
/// never checks whether the named entry exists.
pub fn file_kind(name : String) -> FileKind {
  let extension = extension_of(name)
  match extension {
    Some(extension) if ["xls", "xlsx", "csv", "tsv", "ods"].contains(extension) =>
      Spreadsheet
    Some(extension) if ["doc", "docx", "odt", "rtf"].contains(extension) =>
      Document
    Some(extension) if ["ppt", "pptx", "odp"].contains(extension) =>
      Presentation
    Some(extension) if ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(
        extension,
      ) => Image
    Some(extension) if extension == "pdf" => Pdf
    Some(extension) if ["zip", "tar", "gz", "tgz", "bz2", "7z", "rar"].contains(
        extension,
      ) => Archive
    Some(extension) if [
        "mbt", "mbti", "mbtx", "js", "ts", "jsx", "tsx", "py", "rs", "go", "java",
        "kt", "rb", "php", "swift", "cs", "lua", "sh", "css", "scss", "html", "htm",
        "sql", "xml",
      ].contains(extension) => Code
    Some(extension) if [
        "txt", "md", "markdown", "json", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "log",
      ].contains(extension) => Text
    _ => Generic
  }
}

///|
test "workspace file references accept portable relative paths" {
  let reference = parse(FenceLanguage, "reports\\matrix.xlsx", closed=true).unwrap()
  assert_eq(reference.path, "reports\\matrix.xlsx")
  assert_eq(reference.name, "matrix.xlsx")
  assert_eq(reference.extension, Some("xlsx"))
  assert_eq(reference.kind, Spreadsheet)
}

///|
test "file kinds provide icon paths" {
  let paths = [
    file_icon_path(Spreadsheet),
    file_icon_path(Document),
    file_icon_path(Presentation),
    file_icon_path(Image),
    file_icon_path(Pdf),
    file_icon_path(Archive),
    file_icon_path(Code),
    file_icon_path(Text),
    file_icon_path(Generic),
  ]
  for path in paths {
    assert_true(!path.is_empty())
  }
  assert_true(file_icon_path(Spreadsheet) != file_icon_path(Document))
  assert_true(file_icon_path(Presentation) != file_icon_path(Image))
}

///|
test "file kinds are shared by compact file views" {
  assert_eq(file_kind("matrix.xlsx"), Spreadsheet)
  assert_eq(file_kind("notes.md"), Text)
  assert_eq(file_kind("src/main.mbt"), Code)
  assert_eq(file_kind("README"), Generic)
}

///|
test "workspace file references reject unsafe and incomplete paths" {
  for
    path in [
      "", "../secret.txt", "reports/../../secret.txt", "/tmp/secret.txt", "C:\\secret.txt",
      "file:///tmp/secret.txt", "reports/", "reports/a.txt\nother.txt",
    ] {
    assert_true(parse(FenceLanguage, path, closed=true) is None)
  }
  assert_true(parse(FenceLanguage, "reports/a.txt", closed=false) is None)
  assert_true(parse("text", "reports/a.txt", closed=true) is None)
}

///|
test "markdown parts replace only closed valid file fences" {
  let parts = markdown_parts(
    "intro\n\n```openseek-file\nreports/matrix.xlsx\n```\n\noutro",
  )
  assert_eq(parts.length(), 3)
  assert_true(parts[0] is Text(text) && text.has_prefix("intro"))
  assert_true(parts[1] is File(reference) && reference.name == "matrix.xlsx")
  assert_true(parts[2] is Text(text) && text.has_suffix("outro"))
  let unfinished = markdown_parts("```openseek-file\nreports/a.txt")
  assert_eq(unfinished.length(), 1)
  assert_true(unfinished[0] is Text(text) && text.contains("openseek-file"))
}
