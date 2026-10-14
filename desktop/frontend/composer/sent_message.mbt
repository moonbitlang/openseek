///|
/// Recover a sent prompt as an editable draft, preserving mention chips and images.
/// Provider-owned files have no composer representation and cannot be edited.
pub fn Draft::from_content(content : @deepseek.Content) -> Draft? {
  let images : Array[Image] = []
  for part in content.0 {
    match part {
      Text(_) => ()
      ImageUrl(url~) => images.push({ name: "Image", url, })
      // A provider-owned file cannot be represented by the composer's image
      // data. Do not offer an edit that would silently discard it.
      File(..) => return None
    }
  }
  let text = content.text()
  if @mention_context.parse(text) is Some(parsed) {
    Some({
      task: parsed.task,
      mentions: parsed.mentions.map(ref_ => { ref_, range: None, }),
      images,
    })
  } else {
    Some({ task: text, mentions: [], images, })
  }
}
