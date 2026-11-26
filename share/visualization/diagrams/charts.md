# Quantitative charts

Use a chart when the shape of the data matters more than reading individual
values. Use a Markdown table when the reader needs a few exact values.

Use MoonPlot (`Lampese/mathplotlib`) for both interactive and static charts. It
renders self-contained SVG with the bundled MoonBit toolchain and needs no
Python runtime.

| Question | Chart & MoonPlot (`@mathplotlib`) API |
| --- | --- |
| How did a measurement change over time? | Line chart (`axes.plot`, `axes.plot_date`, `axes.fill_between`). Put time on the horizontal axis and leave gaps for missing observations. |
| How do categories compare? | Bar chart (`axes.bar_category`, `axes.grouped_bar`, `axes.stacked_bar`, `axes.barh`). Start the value axis at zero so bar lengths are comparable. |
| How are values distributed or uncertain? | Distribution plot (`axes.hist`, `axes.boxplot`, `axes.violinplot`, `axes.errorbar`). Use consistent bins when comparing distributions and label the count or density axis. |
| How are two measurements or a grid related? | Scatter or matrix plot (`axes.scatter`, `axes.imshow`, `axes.hist2d`, `axes.hexbin`). Use one point per observation; correlation alone does not establish cause. |
| How does a total break down into parts? | Pie or donut chart (`axes.pie`, `axes.donut`) for a few proportions that sum to a whole; prefer bars when precise comparison matters. |

Label axes with units and give enough context to interpret the data, such as the
period and source. State the takeaway in prose instead of repeating every label.

## Interactive charts (preferred for exploration)

When hover inspection, series toggling, selection, or input controls help answer
the question, build an [interactive HTML artifact](../artifacts.md#interactive-answers)
from `<bundled-resources>/artifact/rabbita/` (`init.mbtx`, `write.mbtx`,
`build.mbtx`). That starter already pins `Lampese/mathplotlib` and
`Lampese/mathplotlib/rabbita` (`@plot_dom`).

`@plot_dom.view` supports hover/click picking, line x-snapping
(`hit_mode=XNearest`), interactive legend toggles (`legend` + `ToggleSeries`),
and custom tooltips (`tooltip=info => ...`):

```moonbit nocheck
let chart = figure.to_drawing()
@plot_dom.view(
  chart,
  id="comparison-chart",
  on_event=event => emit(Chart(event)),
  hovered?=model.hovered,
  selected?=model.selected,
  hit_mode=XNearest,
  legend=[
    @plot_dom.legend_item("actual", "Actual", "#2563eb", model.show_actual),
    @plot_dom.legend_item("target", "Target", "#d97706", model.show_target),
  ],
)
```

Keep control and chart chrome legible in both light and dark themes using
`light-dark(...)` and `[data-theme]`, and avoid hardcoding a non-responsive
width on the rendered SVG.

## Static SVG charts

When a static figure is sufficient and no controls or hover tooltips are needed,
generate SVG directly with `Lampese/mathplotlib` (`figure.to_svg_checked()`),
save it under `<session scratch>/artifact/<name>.svg`, and reference it with an
`openseek-file artifact` fence (or `openseek-file` for a downloadable file
card; see [file artifacts](../artifacts.md#storage-and-references)).
