# Choosing diagrams and charts in SeekMoon

Use a diagram when it makes a branch, boundary, dependency, or message order
easier to grasp than prose. Use an ordered list for a simple series of steps or a
Markdown table for a few exact values. If the user asks for a format, or the
project already uses one, prefer it when it fits the job and the destination.

| What the reader needs to see | Guide |
| --- | --- |
| Workflows or state transitions that benefit from automatic layout | [Mermaid](mermaid.md) |
| A flowchart with a few steps or branches, especially if the nodes or arrows contain formulas | [Draw with KaTeX block math](katex.md) |
| Components, ownership boundaries, imports, or data flow | [Diago / D2](diago.md) |
| Who sends what to whom and in what order, or how classes and interfaces relate | [PlantUML](plantuml.md); Mermaid also supports sequence diagrams |
| Trends, comparisons, distributions, or correlation in numeric data | [Quantitative charts](charts.md) |
| How a result changes when the reader adjusts inputs | [Interactive HTML artifacts](../artifacts.md#interactive-answers) |

Read only the selected guide. In the SeekMoon transcript, use complete Markdown
fences with the exact lowercase language names for Mermaid, Diago, and PlantUML.
Incomplete or invalid diagram fences stay as source. Use `$$` delimiters instead
for KaTeX block math. Neither form needs an external renderer or image file.
Outside SeekMoon, check what the destination supports before relying on inline
rendering.

Show only the elements that matter to the question. Explain what the reader
should take away instead of repeating the labels in prose.
