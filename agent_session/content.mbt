///|
pub using @protocol {
  type Content,
  type ContentPart,
  type Image,
  type ImageError,
}

///|
/// Project durable parts into API content without changing stored history.
pub fn to_deepseek_parts(content : Content) -> Array[@deepseek.ContentPart] {
  content.0.map(part => {
    match part {
      Text(text) => Text(text)
      Image(image) => ImageUrl(url=image.data_url())
      ImageRef(reference) => ImageUrl(url=reference.url())
    }
  })
}

///|
/// Transform image-bearing content while preserving every event's metadata.
pub async fn SessionItem::map_content(
  self : SessionItem,
  transform : async (Content) -> Content,
) -> SessionItem {
  match self {
    User(message) => User({ ..message, content: transform(message.content), })
    Tool(result) => Tool({ ..result, content: transform(result.content), })
    _ => self
  }
}

///|
/// Transform a snapshot without changing event identities or timestamps.
pub async fn Session::map_content(
  self : Session,
  transform : async (Content) -> Content,
) -> Session {
  let mut events = @vector.from_array([])
  for event in self.events {
    events = events.push(event.map_content(transform))
  }
  { ..self, events, }
}

///|
/// Whether the item requires the attachment-aware session format.
pub fn SessionItem::has_image_refs(self : SessionItem) -> Bool {
  match self {
    User(message) => message.content.0.any(part => part is ImageRef(_))
    Tool(result) => result.content.0.any(part => part is ImageRef(_))
    _ => false
  }
}

///|
/// Transform event content while retaining its original sequence and timestamp.
pub async fn SessionEvent::map_content(
  self : SessionEvent,
  transform : async (Content) -> Content,
) -> SessionEvent {
  { ..self, item: self.item.map_content(transform), }
}
