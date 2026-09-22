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
    }
  })
}
