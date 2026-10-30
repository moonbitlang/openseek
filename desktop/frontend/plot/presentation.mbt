///|
priv struct Labels {
  chart : String
  chart_data : String
  category : String
  value : String
  range : String
  count : String
  share : String
}

///|
fn labels(locale : @i18n.Locale) -> Labels {
  match locale {
    English =>
      {
        chart: "Chart",
        chart_data: "Chart data",
        category: "Category",
        value: "Value",
        range: "Range",
        count: "Count",
        share: "Share",
      }
    SimplifiedChinese =>
      {
        chart: "图表",
        chart_data: "图表数据",
        category: "类别",
        value: "数值",
        range: "区间",
        count: "频数",
        share: "占比",
      }
    TraditionalChinese =>
      {
        chart: "圖表",
        chart_data: "圖表資料",
        category: "類別",
        value: "數值",
        range: "區間",
        count: "次數",
        share: "佔比",
      }
    Japanese =>
      {
        chart: "グラフ",
        chart_data: "グラフのデータ",
        category: "カテゴリ",
        value: "値",
        range: "区間",
        count: "度数",
        share: "割合",
      }
    Spanish =>
      {
        chart: "Gráfico",
        chart_data: "Datos del gráfico",
        category: "Categoría",
        value: "Valor",
        range: "Intervalo",
        count: "Frecuencia",
        share: "Proporción",
      }
  }
}

///|
fn Spec::supports_picking(self : Spec) -> Bool {
  self.series.any(series => series.kind != "area")
}

///|
fn Spec::view(
  self : Spec,
  drawing : @mathplotlib.Drawing,
  selection : Selection,
  id~ : String,
  locale~ : @i18n.Locale,
  on_event~ : @cmd.Emit[@plot_dom.Interaction],
) -> @html.Html raise @plot_dom.AdapterError {
  let text = labels(locale)
  let picking = self.supports_picking()
  let children = [
    @html.div(class="chat-plot-y-label", self.y_label),
    @plot_dom.view(
      drawing,
      id~,
      on_event=event => on_event(event),
      hovered?=selection.hovered,
      selected?=selection.selected,
      hit_mode=@mathplotlib.HitMode::XNearest,
      tooltip=info => self.tooltip(info, selection.hidden, locale),
      legend=self.series.mapi((i, series) => {
        @plot_dom.legend_item(
          i.to_string(),
          series.display_name(i),
          series.color(i),
          !selection.hidden.contains(i),
        )
      }),
    ),
  ]
  @html.div(
    class="chat-plot",
    attrs=@html.Attrs::build()
      .role("group")
      .aria_label(if self.title.is_empty() { text.chart } else { self.title })
      .data_set("plot-picking", picking.to_string()),
    children,
  )
}
