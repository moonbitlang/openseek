Explanatory diagrams drawn with KaTeX boxes and arrows.

# Drawing flowcharts with KaTeX block math

KaTeX can draw a flowchart from ordinary boxes and arrows, with text, formulas,
or both as labels. The same technique works for a few connected components.
For specific diagram types and features beyond KaTeX, see the
`diagrams` guide.

In SeekMoon, put `$$` on separate opening and closing lines, with no code fence
around the block.

## A short workflow

Make a node with `\boxed{...}` and put prose inside `\text{...}`. Connect the
nodes with `\longrightarrow`, or use `\xrightarrow{...}` when an arrow needs a
label.

$$
\boxed{\text{Submit request}} \longrightarrow
\boxed{\text{Review request}} \longrightarrow
\boxed{\text{Notify requester}}
$$

## A decision with formulas

Use `\begin{array}{...}` to place nodes and arrows on a grid: `&` separates
columns and `\\` ends a row. Leave cells empty to line up the incoming arrow
with the decision. Label each outgoing arrow with its condition or outcome.
Here the two branches compute $y=|x|$.

$$
\begin{array}{ccccc}
 & & \boxed{\text{Input }x} & & \\
 & & \downarrow & & \\
\boxed{y=x} & \xleftarrow{\text{yes}} & \boxed{x\ge 0\,?} &
\xrightarrow{\text{no}} & \boxed{y=-x}
\end{array}
$$

Keep the grid narrow enough to read in the transcript. KaTeX does not route
edges or rearrange the chart as it grows, and does not run TikZ.
