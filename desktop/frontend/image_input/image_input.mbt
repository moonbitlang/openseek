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
extern "js" fn BrowserFile::name(self : BrowserFile) -> String =
  #| file => file.name

///|
extern "js" fn BrowserFile::blob(self : BrowserFile) -> @dom.Blob =
  #| file => file

///|
/// A one-shot native picker owns its change/cancel listeners. File inputs emit
/// ordinary Event, which Rabbita's InputEvent-only Attrs::on_change rejects.
extern "js" fn Selection::pick(
  on_files : (FixedArray[BrowserFile]) -> Unit,
) -> Unit =
  #| onFiles => {
  #|   const input = document.createElement('input');
  #|   input.type = 'file';
  #|   input.accept = 'image/png,image/jpeg,image/webp,image/gif';
  #|   input.multiple = true;
  #|   input.hidden = true;
  #|   input.addEventListener('change', () => {
  #|     const files = Array.from(input.files || []);
  #|     input.remove();
  #|     onFiles(files);
  #|   }, { once: true });
  #|   input.addEventListener('cancel', () => input.remove(), { once: true });
  #|   document.body.append(input);
  #|   input.click();
  #| }

///|
/// Snapshot DataTransfer and prevent the default synchronously in the DOM
/// callback. A returned command runs too late to prevent native paste/drop.
extern "js" fn Selection::pasted(
  event : @dom.ClipboardEvent,
) -> FixedArray[BrowserFile] =
  #| event => {
  #|   const files = Array.from(event.clipboardData?.files || []);
  #|   if (files.length) event.preventDefault();
  #|   return files;
  #| }

///|
extern "js" fn Selection::dropped(
  event : @dom.DragEvent,
) -> FixedArray[BrowserFile] =
  #| event => {
  #|   const files = Array.from(event.dataTransfer?.files || []);
  #|   if (files.length) event.preventDefault();
  #|   return files;
  #| }

///|
extern "js" fn Selection::dragged(event : @dom.DragEvent) -> Unit =
  #| event => {
  #|   if (Array.from(event.dataTransfer?.types || []).includes('Files')) {
  #|     event.preventDefault();
  #|     event.dataTransfer.dropEffect = 'copy';
  #|   }
  #| }

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
    @js.async_run(() => {
      let result = self.load(locale~) catch {
        error => {
          scheduler.add(
            emit(
              Failed(
                if locale is SimplifiedChinese {
                  "无法读取图片：\{error}"
                } else {
                  "Could not read images: \{error}"
                },
              ),
            ),
          )
          return
        }
      }
      scheduler.add(emit(result))
    })
  })
}

///|
async fn Selection::load(
  locale? : @i18n.Locale = English,
  self : Selection,
) -> Event {
  if self.0.length() > 4 {
    return Failed(
      if locale is SimplifiedChinese {
        "每条消息最多可附加 4 张图片。"
      } else {
        "Attach up to 4 images per message."
      },
    )
  }
  for file in self.0 {
    let blob = file.blob()
    if blob.get_size() > 5 * 1024 * 1024 {
      return Failed(
        if locale is SimplifiedChinese {
          "每张图片不得超过 5 MiB：\{file.name()}"
        } else {
          "Each image must be 5 MiB or smaller: \{file.name()}"
        },
      )
    }
    if blob.get_size() == 0 {
      return Failed(
        if locale is SimplifiedChinese {
          "图片为空：\{file.name()}"
        } else {
          "Image is empty: \{file.name()}"
        },
      )
    }
    match blob.get_type() {
      "image/png" | "image/jpeg" | "image/webp" | "image/gif" => ()
      _ =>
        return Failed(
          if locale is SimplifiedChinese {
            "请选择 PNG、JPEG、WebP 或 GIF 图片：\{file.name()}"
          } else {
            "Choose PNG, JPEG, WebP or GIF images: \{file.name()}"
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
