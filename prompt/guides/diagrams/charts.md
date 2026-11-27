# Quantitative charts

Use a chart when the shape of the data matters more than reading individual
values. Use a Markdown table when the reader needs a few exact values.

| Question | Chart |
| --- | --- |
| How did a measurement change over time? | Line chart. Put time on the horizontal axis and leave gaps for missing observations. |
| How do categories compare? | Bar chart. Start the value axis at zero so bar lengths are comparable. |
| How are values distributed? | Histogram. Use consistent bins when comparing distributions and label the count or density axis. |
| How are two measurements related? | Scatter plot. Use one point per observation; correlation alone does not establish cause. |

Label axes with units and give enough context to interpret the data, such as the
period and source. Use an available plotting tool such as Matplotlib for a static
plot, save it, and reference it as a file artifact.
If changing inputs or filters is part of the answer, use an interactive HTML
artifact instead. See `artifacts` for storage, references, and interactive answers.
