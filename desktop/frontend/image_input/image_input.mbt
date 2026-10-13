///|
/// Events contain plain data only. Browser File handles never enter a model.
pub(all) enum Event {
  Reading
  Ready(Array[(String, String)])
  DocumentsReady(
    images~ : Array[(String, String)],
    documents~ : Array[Document]
  )
  NativeReady(String?)
  Failed(String)
}

///|
/// A browser-selected document is plain data. Only a local host may use its
/// native path; a remote host always receives the selected bytes.
pub(all) struct Document {
  name : String
  data_base64 : String
  native_path : String?
} derive(Debug, Eq)

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend Document with Debug::{to_repr}

///|
fn document_name(name : String) -> Bool {
  let name = name.to_lower()
  name.has_suffix(".pdf") ||
  name.has_suffix(".docx") ||
  name.has_suffix(".xlsx")
}

///|
extern "js" fn BrowserFile::native_path(
  self : BrowserFile,
) -> @js.Nullable[String] =
  #| file => {
  #|   if (typeof file.path !== "string" || file.path.length === 0) return null;
  #|   if (/^[a-zA-Z]:[\\/]/.test(file.path)) {
  #|     return "/" + file.path[0].toLowerCase() + file.path.slice(1).replaceAll("\\", "/");
  #|   }
  #|   return file.path;
  #| }

///|
#external
priv type BrowserFile

///|
priv struct Selection(FixedArray[BrowserFile])

///|
fn BrowserFile::name(self : BrowserFile) -> String {
  @js.Value::cast_from(self).get_with_string("name")
}

///|
fn BrowserFile::blob(self : BrowserFile) -> @dom.Blob {
  @js.Value::cast_from(self).cast()
}

///|
/// Listen to ordinary Event: Rabbita's view-level on_change expects InputEvent.
fn Selection::pick(
  on_files : (FixedArray[BrowserFile]) -> Unit,
  allow_images~ : Bool,
) -> Unit {
  let input = @dom.document().create_element("input")
  input.set_attribute("type", "file")
  input.set_attribute(
    "accept",
    if allow_images {
      "image/png,image/jpeg,image/webp,image/gif,.pdf,.docx,.xlsx"
    } else {
      ".pdf,.docx,.xlsx"
    },
  )
  input.set_attribute("multiple", "")
  input.set_attribute("hidden", "")
  input.add_event_listener_with_options(
    "change",
    _ => {
      let files = browser_files(@js.Value::cast_from(input))
      remove_file_input(input)
      on_files(files)
    },
    once=true,
  )
  input.add_event_listener_with_options(
    "cancel",
    _ => remove_file_input(input),
    once=true,
  )
  if @dom.document().get_body() is Some(body) {
    body.append_child(input.as_node())
  }
  if input.to_html_element() is Some(element) {
    element.click()
  }
}

///|
/// Snapshot files and prevent default synchronously, before dispatching a command.
fn Selection::pasted(event : @dom.ClipboardEvent) -> FixedArray[BrowserFile] {
  let data : @js.Nullable[@js.Value] = @js.Value::cast_from(event).get_with_string(
    "clipboardData",
  )
  let files = match data.to_option() {
    Some(data) => browser_files(data)
    None => []
  }
  if files.length() > 0 {
    event.prevent_default()
  }
  files
}

///|
/// Snapshot files and prevent default synchronously, before dispatching a command.
fn Selection::dropped(event : @dom.DragEvent) -> FixedArray[BrowserFile] {
  let data : @js.Nullable[@js.Value] = @js.Value::cast_from(event).get_with_string(
    "dataTransfer",
  )
  let files = match data.to_option() {
    Some(data) => browser_files(data)
    None => []
  }
  if files.length() > 0 {
    event.prevent_default()
  }
  files
}

///|
fn Selection::dragged(event : @dom.DragEvent) -> Unit {
  let data : @js.Nullable[@js.Value] = @js.Value::cast_from(event).get_with_string(
    "dataTransfer",
  )
  guard data.to_option() is Some(data) else { return }
  let types : @js.Nullable[@js.Value] = data.get_with_string("types")
  guard types.to_option() is Some(types) else { return }
  let array : @js.Value = @js.globalThis.get_with_string("Array")
  let types : FixedArray[String] = array.apply_with_string("from", [types])
  if types.iter().any(t => t == "Files") {
    event.prevent_default()
    data.set_with_string("dropEffect", "copy")
  }
}

///|
/// Open only when this command executes in response to the user's click.
pub fn pick(
  locale~ : @i18n.Locale = English,
  allow_images~ : Bool = true,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    Selection::pick(
      files => {
        scheduler.add(Selection(files).read(locale~, allow_images~, emit))
      },
      allow_images~,
    )
  })
}

///|
/// Event adapters are called only inside DOM callbacks, never by update/view.
/// Capturing files is synchronous; byte reads and result delivery are commands.
pub fn pasted(
  locale~ : @i18n.Locale = English,
  allow_images~ : Bool = true,
  event : @dom.ClipboardEvent,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  Selection(Selection::pasted(event)).read(locale~, allow_images~, emit)
}

///|
pub fn dropped(
  locale~ : @i18n.Locale = English,
  allow_images~ : Bool = true,
  event : @dom.DragEvent,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  Selection(Selection::dropped(event)).read(locale~, allow_images~, emit)
}

///|
pub fn dragged(event : @dom.DragEvent) -> @cmd.Cmd {
  Selection::dragged(event)
  @cmd.none
}

///|
/// Bound allocations before reading. A failed batch adds no partial selection;
/// previously attached images remain editable and can still be submitted.
fn Selection::read(
  locale~ : @i18n.Locale = English,
  allow_images~ : Bool = true,
  self : Selection,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  if self.0.is_empty() {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    scheduler.add(emit(Reading))
    @js.Promise::from_async(() => {
      let result = self.load(locale~, allow_images~) catch {
        error => {
          scheduler.add(
            emit(
              Failed(
                match locale {
                  SimplifiedChinese => "无法读取附件：\{error}"
                  TraditionalChinese => "無法讀取附件：\{error}"
                  Japanese =>
                    "添付ファイルを読み取れません：\{error}"
                  English => "Could not read attachments: \{error}"
                  Spanish =>
                    "No se pudieron leer los archivos adjuntos: \{error}"
                },
              ),
            ),
          )
          return
        }
      }
      scheduler.add(emit(result))
    })
    |> ignore
  })
}

///|
async fn Selection::load(
  locale~ : @i18n.Locale = English,
  allow_images~ : Bool = true,
  self : Selection,
) -> Event {
  for file in self.0 {
    let blob = file.blob()
    if document_name(file.name()) {
      if blob.get_size() == 0 || blob.get_size() > 20 * 1024 * 1024 {
        return Failed(
          match locale {
            SimplifiedChinese =>
              "文档不能为空且不得超过 20 MiB：\{file.name()}"
            TraditionalChinese =>
              "文件不能為空且不得超過 20 MiB：\{file.name()}"
            Japanese =>
              "文書は空でなく、20 MiB 以下にしてください：\{file.name()}"
            English =>
              "Documents must be nonempty and 20 MiB or smaller: \{file.name()}"
            Spanish =>
              "Los documentos deben tener contenido y ocupar 20 MiB o menos: \{file.name()}"
          },
        )
      }
      continue
    }
    if !allow_images {
      return Failed(
        match locale {
          SimplifiedChinese =>
            "当前模型不支持图片，请选择 PDF、DOCX 或 XLSX 文档。"
          TraditionalChinese =>
            "目前模型不支援圖片，請選擇 PDF、DOCX 或 XLSX 文件。"
          Japanese =>
            "このモデルは画像をサポートしていません。PDF、DOCX、XLSX の文書を選択してください。"
          English =>
            "This model does not support images. Choose PDF, DOCX or XLSX documents."
          Spanish =>
            "Este modelo no admite imágenes. Elige documentos PDF, DOCX o XLSX."
        },
      )
    }
    if blob.get_size() > 5 * 1024 * 1024 {
      return Failed(
        match locale {
          SimplifiedChinese => "每张图片不得超过 5 MiB：\{file.name()}"
          TraditionalChinese =>
            "每張圖片不得超過 5 MiB：\{file.name()}"
          Japanese =>
            "画像は 1 枚あたり 5 MiB 以下にしてください：\{file.name()}"
          English => "Each image must be 5 MiB or smaller: \{file.name()}"
          Spanish => "Cada imagen debe ocupar 5 MiB o menos: \{file.name()}"
        },
      )
    }
    if blob.get_size() == 0 {
      return Failed(
        match locale {
          SimplifiedChinese => "图片为空：\{file.name()}"
          TraditionalChinese => "圖片為空：\{file.name()}"
          Japanese => "画像が空です：\{file.name()}"
          English => "Image is empty: \{file.name()}"
          Spanish => "La imagen está vacía: \{file.name()}"
        },
      )
    }
    match blob.get_type() {
      "image/png" | "image/jpeg" | "image/webp" | "image/gif" => ()
      _ =>
        return Failed(
          match locale {
            SimplifiedChinese =>
              "请选择 PNG、JPEG、WebP、GIF 图片或 PDF、DOCX、XLSX 文档：\{file.name()}"
            TraditionalChinese =>
              "請選擇 PNG、JPEG、WebP、GIF 圖片或 PDF、DOCX、XLSX 文件：\{file.name()}"
            Japanese =>
              "PNG、JPEG、WebP、GIF の画像、または PDF、DOCX、XLSX の文書を選択してください：\{file.name()}"
            English =>
              "Choose PNG, JPEG, WebP or GIF images, or PDF, DOCX or XLSX documents: \{file.name()}"
            Spanish =>
              "Elige imágenes PNG, JPEG, WebP o GIF, o documentos PDF, DOCX o XLSX: \{file.name()}"
          },
        )
    }
  }
  let images : Array[(String, String)] = []
  let documents : Array[Document] = []
  for file in self.0 {
    let blob = file.blob()
    let bytes = blob.bytes()
    if document_name(file.name()) {
      documents.push({
        name: file.name(),
        data_base64: @base64.encode(bytes),
        native_path: file.native_path().to_option(),
      })
      continue
    }
    images.push(
      (file.name(), "data:\{blob.get_type()};base64,\{@base64.encode(bytes)}"),
    )
  }
  if documents.is_empty() {
    Ready(images)
  } else {
    DocumentsReady(images~, documents~)
  }
}

///|
fn browser_files(source : @js.Value) -> FixedArray[BrowserFile] {
  let files : @js.Nullable[@js.Value] = source.get_with_string("files")
  guard files.to_option() is Some(files) else { return [] }
  let array : @js.Value = @js.globalThis.get_with_string("Array")
  array.apply_with_string("from", [files])
}

///|
fn remove_file_input(input : @dom.Element) -> Unit {
  let _ : Unit = @js.Value::cast_from(input).apply_with_string(
    "remove",
    ([] : FixedArray[@js.Value]),
  )
}
