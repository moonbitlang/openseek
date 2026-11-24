// Keep captions as text for tooltips and render tool identities separately.

///|
/// Localize goal notices without changing recorded tool names or payloads.
fn tool_display_label(
  locale~ : @i18n.Locale = English,
  name : String,
  label : String,
) -> String {
  if name == "goal" {
    for
      (en, zh, ja, es) in [
        (
          "Goal set", "已设定目标", "目標を設定しました", "Objetivo establecido",
        ),
        (
          "Goal cleared", "已清除目标", "目標をクリアしました", "Objetivo borrado",
        ),
        (
          "Goal blocked", "目标受阻", "目標がブロックされました",
          "Objetivo bloqueado",
        ),
        (
          "Goal resumed", "已恢复目标", "目標を再開しました", "Objetivo reanudado",
        ),
      ] {
      let (localized, separator) = match locale {
        English => (en, ": ")
        Spanish => (es, ": ")
        SimplifiedChinese => (zh, "：")
        TraditionalChinese => (zh, "：")
        Japanese => (ja, "：")
      }
      if label == en {
        return localized
      }
      if label.strip_prefix(en + ": ") is Some(rest) {
        return localized + separator + rest.to_owned()
      }
    }
  }
  label
}

///|
/// The same tool identity in detailed and minimal transcripts; lifecycle
/// status remains independent of this icon.
fn tool_caption_icon(name : String) -> @html.Html? {
  match name {
    "mbtx" => Some(@icons.icon_terminal())
    "read_image" => Some(@icons.icon_file_media())
    "edit" => Some(@icons.icon_edit())
    "multi_edit" => Some(@icons.icon_diff_multiple())
    "job_output" => Some(@icons.icon_arrow_down())
    "job_wait" => Some(@icons.icon_watch())
    "job_stop" => Some(@icons.icon_debug_stop())
    "runtime notice" => Some(@icons.icon_bell())
    _ => None
  }
}

///|
/// Omit only a leading family word already represented by the icon. Keep a
/// brief's own wording, including words that merely share the tool's prefix.
fn tool_caption_text(name : String, label : String) -> String {
  let prefixes = match name {
    "edit" => ["edit", "edited"]
    "job_output" => ["job_output", "job"]
    "mbtx"
    | "read_image"
    | "multi_edit"
    | "job_wait"
    | "job_stop"
    | "runtime notice" => [name]
    _ => return label
  }
  for prefix in prefixes {
    if label == prefix {
      return ""
    }
    if label.strip_prefix(prefix + " ") is Some(rest) {
      return rest.to_owned()
    }
  }
  label
}

///|
fn tool_caption_view(
  name : String,
  label : String,
  background~ : Bool = false,
) -> @html.Html {
  guard tool_caption_icon(name) is Some(icon) else { return @html.text(label) }
  let text = tool_caption_text(name, label)
  @html.span(
    class="tool-caption",
    [
      @html.span(
        class="tool-caption-icon",
        attrs=@html.Attrs::build().role("img").aria_label(name).title(name),
        icon,
      ),
      ..if background {
        [
          @html.text(" "),
          @html.span(
            class="tool-caption-icon",
            attrs=@html.Attrs::build().aria_hidden("true"),
            @icons.icon_arrow_right(),
          ),
        ]
      } else {
        []
      },
      @html.text(if text.is_empty() { "" } else { " " + text }),
    ],
  )
}
