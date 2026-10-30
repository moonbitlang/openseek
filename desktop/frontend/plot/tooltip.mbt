///|
// Every admitted series emits one artist; hidden series are omitted from the
// drawing. Resolve the current frame's artist index before formatting its data.
fn Spec::series_for_hit(
  self : Spec,
  hidden : Array[Int32],
  artist : Int32,
) -> (Int32, Series)? {
  let mut visible = 0
  for index, series in self.series {
    if hidden.contains(index) {
      continue
    }
    if visible == artist {
      return Some((index, series))
    }
    visible += 1
  }
  None
}

///|
fn axis_name(label : String, fallback : String) -> String {
  if label.is_empty() {
    fallback
  } else {
    label
  }
}

///|
fn tooltip_row(label : String, value : String) -> @html.Html {
  @html.span(class="moonplot-coordinate", [
    @html.span(class="moonplot-coordinate-label", label),
    @html.b(value),
  ])
}

///|
fn Spec::tooltip(
  self : Spec,
  info : @mathplotlib.HitInfo,
  hidden : Array[Int32],
  locale : @i18n.Locale,
) -> @html.Html {
  let text = labels(locale)
  let (series, category) = match
    self.series_for_hit(hidden, info.point.artist_index) {
    Some((index, series)) => {
      let category = if info.kind == Histogram {
        info.category
      } else {
        match series.labels.get(info.point.point_index) {
          Some(label) => Some(label)
          None => info.category
        }
      }
      (series.display_name(index), category)
    }
    None => (info.series, info.category)
  }
  let rows = []
  if category is Some(category) {
    let name = match info.kind {
      BarH => axis_name(self.y_label, text.category)
      Pie => text.category
      _ => axis_name(self.x_label, text.category)
    }
    rows.push(tooltip_row(name, category))
  }
  match info.kind {
    Line | Scatter => {
      if category is None {
        rows.push(
          tooltip_row(
            axis_name(self.x_label, "x"),
            info.point.data_x.to_string(),
          ),
        )
      }
      rows.push(
        tooltip_row(axis_name(self.y_label, "y"), info.value.to_string()),
      )
    }
    Bar | BarH => {
      let horizontal = info.kind == BarH
      if category is None {
        rows.push(
          tooltip_row(
            if horizontal {
              axis_name(self.y_label, "y")
            } else {
              axis_name(self.x_label, "x")
            },
            (if horizontal { info.point.data_y } else { info.point.data_x }).to_string(),
          ),
        )
      }
      rows.push(
        tooltip_row(
          axis_name(
            if horizontal {
              self.x_label
            } else {
              self.y_label
            },
            text.value,
          ),
          info.value.to_string(),
        ),
      )
    }
    Histogram => {
      if info.interval is Some((lower, upper)) {
        rows.push(tooltip_row(text.range, "\{lower} – \{upper}"))
      }
      rows.push(tooltip_row(text.count, info.value.to_string()))
    }
    Pie => {
      rows.push(
        tooltip_row(axis_name(self.y_label, text.value), info.value.to_string()),
      )
      if info.fraction is Some(fraction) {
        let percent = (fraction * 10000.0).round() / 100.0
        rows.push(tooltip_row(text.share, "\{percent}%"))
      }
    }
    // Newer renderers can expose additional picking kinds, such as a filled
    // area's band. Keep their value visible in saved charts as well.
    _ => rows.push(tooltip_row(text.value, info.value.to_string()))
  }
  let children = []
  if !series.is_empty() {
    children.push(@html.b(class="moonplot-tooltip-series", series))
  }
  children.push(@html.div(class="moonplot-tooltip-values", rows))
  @html.div(class="moonplot-tooltip-content", children)
}
