///|
/// Level configuration: a root level plus per-category overrides.
///
/// Category overrides are hierarchical: `app.db.query` falls back to
/// `app.db`, then `app`, then the root level.
priv struct Config {
  mut level : Level
  levels : Map[String, Level]
}

///|
/// The configuration `spec` describes, or `None` when it is malformed.
///
/// `spec` is a comma-separated list of directives, each either a root level
/// such as `debug` or a category override such as `transport=trace`. This is
/// the `MOON_XLOG` syntax the desktop inherited from `tonyfettes/xlog`; like
/// xlog, a malformed value is ignored as a whole.
fn Config::parse(spec : String, level~ : Level) -> Config? {
  let config = { level, levels: Map([]), }
  if spec.is_blank() {
    return Some(config)
  }
  for raw in spec.split(",") {
    let directive = raw.trim()
    guard !directive.is_blank() else { return None }
    if directive.split_once("=") is Some((category, name)) {
      let category = category.trim()
      guard is_valid_category(category) && parse_level(name.trim()) is Some(l) else {
        return None
      }
      config.levels[category.to_owned()] = l
    } else {
      guard parse_level(directive) is Some(l) else { return None }
      config.level = l
    }
  }
  Some(config)
}

///|
fn is_valid_category(category : StringView) -> Bool {
  !category.is_empty() &&
  !category.has_prefix(".") &&
  !category.has_suffix(".") &&
  !category.contains("..")
}

///|
/// The level that applies to `category`.
fn Config::effective_level(self : Config, category : String?) -> Level {
  for current = category {
    guard current is Some(name) else { break self.level }
    if self.levels.get(name) is Some(level) {
      break level
    }
    continue name.rev_split_once(".").map(pair => pair.0.to_owned())
  }
}
