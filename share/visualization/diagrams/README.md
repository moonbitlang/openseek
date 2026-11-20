# Choosing diagrams and charts in SeekMoon

Use a diagram when it makes a branch, boundary, dependency, or message order
easier to grasp than prose. Use an ordered list for a simple series of steps or a
Markdown table for a few exact values. Honor an explicitly requested format or
one required by the project.

Use [KaTeX block math](katex.md) by default for explanatory diagrams. Its boxes
and arrows can contain plain text or formulas and can show steps, decisions, or
connections between components.

Use Mermaid, PlantUML, or Diago/D2 only when the task calls for a specific diagram type below or KaTeX cannot provide a required feature. A workflow or architecture question alone does not imply a specialized diagram type.

| Specific diagram type | Guide |
| --- | --- |
| State diagram with named states and transition events, or flowchart that requires automatic layout of branches and loops | [Mermaid](mermaid.md) |
| Sequence diagram with participant lifelines and ordered messages, or class diagram with type relationships | [PlantUML](plantuml.md) |
| Architecture or dependency diagram with nested component boundaries and links across them | [Diago / D2](diago.md) |

For trends, comparisons, distributions, or correlation in numeric data, use
[quantitative charts](charts.md). If readers need to change inputs or filters,
use an [interactive HTML artifact](../artifacts.md#interactive-answers).

Read only the selected guide. In the SeekMoon transcript, use complete Markdown
fences with the exact lowercase language names for Mermaid, Diago, and PlantUML.
Incomplete or invalid diagram fences stay as source. Use `$$` delimiters instead
for KaTeX block math. Neither form needs an external renderer or image file.

Show only the elements that matter to the question. Explain what the reader
should take away instead of repeating the labels in prose.
