///|
/// Browser-owned image bytes encoded as a data URL. This value travels with
/// the draft; a file path on the browser device is never sent to another device.
pub(all) struct Image {
  name : String
  url : String
} derive(Eq, @debug.Debug)

///|
pub fn Draft::is_empty(self : Draft) -> Bool {
  self.task.is_blank() && self.mentions.is_empty() && self.images.is_empty()
}

///|
/// Keep image input separate from prompt text so Codex receives actual pixels.
pub fn Draft::user_item(self : Draft) -> @transcript.ItemKind {
  @transcript.User(
    content=Content(
      [
        Text(self.prompt()),
        ..self.images.map(image => {
          @deepseek.ContentPart::ImageUrl(url=image.url)
        }),
      ],
    ),
  )
}

///|
pub extend Image with Eq::{equal, not_equal}

///|
pub extend Image with @debug.Debug::{to_repr}

///|
/// Removing a preview edits only this draft, including while a previous model
/// snapshot still owns the same attachment array.
fn Draft::without_image(self : Draft, index : Int) -> Draft {
  guard self.images.get(index) is Some(_) else { return self }
  let images = self.images.copy()
  ignore(images.remove(index))
  { ..self, images, }
}

///|
fn Draft::image_previews(
  locale? : @i18n.Locale = English,
  self : Draft,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  self.images.mapi((index, image) => {
    @html.div(class="composer-image", [
      @html.img(src=image.url, alt=image.name, title=image.name),
      @html.button(
        type_="button",
        class="composer-image-remove",
        title=ui(locale, RemoveImage),
        on_click=emit(ImageRemoved(index)),
        attrs=@html.Attrs::build().aria_label(
          ui(locale, RemovePrefix) + image.name,
        ),
        @icons.icon(@icons.icon_close),
      ),
    ])
  })
}
