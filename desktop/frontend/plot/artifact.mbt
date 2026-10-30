///|
/// A conversation-scoped catalog recovered exclusively from structured tool
/// results. Conflicting IDs stay unavailable rather than choosing a version.
pub struct Catalog {
  priv sources : Map[String, String?]
} derive(Eq)

///|
pub fn Catalog::from_tool_data(results : Array[Json?]) -> Catalog {
  let sources : Map[String, String?] = Map([])
  for data in results {
    for chart in @artifact.charts(data) {
      let source = chart.spec.stringify()
      match sources.get(chart.id) {
        None => sources[chart.id] = Some(source)
        Some(previous) if previous != Some(source) => sources[chart.id] = None
        _ => ()
      }
    }
  }
  { sources, }
}

///|
fn Catalog::source(self : Catalog, id : String) -> String? {
  self.sources.get(id).bind(source => source)
}

///|
fn unavailable_chart(locale : @i18n.Locale, alt : String) -> @html.Html {
  let label = match locale {
    English => "Chart unavailable"
    SimplifiedChinese => "图表不可用"
    TraditionalChinese => "圖表無法使用"
    Japanese => "グラフを表示できません"
    Spanish => "Gráfico no disponible"
  }
  @html.div(
    class="chat-plot-unavailable",
    attrs=@html.Attrs::build().role("note"),
    if alt.is_blank() {
      label
    } else {
      "\{alt} · \{label}"
    },
  )
}

///|
pub extend Catalog with Eq::{equal, not_equal}
