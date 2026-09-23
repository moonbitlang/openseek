///|
/// Events contain plain data only. Browser File handles never enter a model.
pub(all) enum Event {
  Reading
  Ready(Array[(String, String)])
  Failed(String)
}

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
fn Selection::pick(on_files : (FixedArray[BrowserFile]) -> Unit) -> Unit {
  let input = @dom.document().create_element("input")
  input.set_attribute("type", "file")
  input.set_attribute("accept", "image/png,image/jpeg,image/webp,image/gif")
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
  locale? : @i18n.Locale = English,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    Selection::pick(files => scheduler.add(Selection(files).read(locale~, emit)))
  })
}

///|
/// Event adapters are called only inside DOM callbacks, never by update/view.
/// Capturing files is synchronous; byte reads and result delivery are commands.
pub fn pasted(
  locale? : @i18n.Locale = English,
  event : @dom.ClipboardEvent,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  Selection(Selection::pasted(event)).read(locale~, emit)
}

///|
pub fn dropped(
  locale? : @i18n.Locale = English,
  event : @dom.DragEvent,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  Selection(Selection::dropped(event)).read(locale~, emit)
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
  locale? : @i18n.Locale = English,
  self : Selection,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  if self.0.is_empty() {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    scheduler.add(emit(Reading))
    @js.Promise::from_async(() => {
      let result = self.load(locale~) catch {
        error => {
          scheduler.add(
            emit(
              Failed(
                match locale {
                  SimplifiedChinese => "无法读取图片：\{error}"
                  TraditionalChinese => "無法讀取圖片：\{error}"
                  Japanese => "画像を読み取れません：\{error}"
                  English => "Could not read images: \{error}"
                  Spanish => "No se pudieron leer las imágenes: \{error}"
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
  locale? : @i18n.Locale = English,
  self : Selection,
) -> Event {
  for file in self.0 {
    let blob = file.blob()
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
              "请选择 PNG、JPEG、WebP 或 GIF 图片：\{file.name()}"
            TraditionalChinese =>
              "請選擇 PNG、JPEG、WebP 或 GIF 圖片：\{file.name()}"
            Japanese =>
              "PNG、JPEG、WebP または GIF の画像を選択してください：\{file.name()}"
            English => "Choose PNG, JPEG, WebP or GIF images: \{file.name()}"
            Spanish => "Elige imágenes PNG, JPEG, WebP o GIF: \{file.name()}"
          },
        )
    }
  }
  let images : Array[(String, String)] = []
  for file in self.0 {
    let blob = file.blob()
    let bytes = blob.bytes()
    images.push(
      (file.name(), "data:\{blob.get_type()};base64,\{@base64.encode(bytes)}"),
    )
  }
  Ready(images)
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
