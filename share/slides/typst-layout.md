# Typst Layout Guidelines

## Compile with the MoonBit Typst CLI

Run the CLI directly with `moonx moonbitlang/typst/cli`. Include
`--ignore-system-fonts` by default to use the bundled fonts:

```sh
moonx moonbitlang/typst/cli -- compile slide.typ slide.pdf --ignore-system-fonts
```

Run this from the directory containing `slide.typ`. `moonx` resolves and runs
the CLI; there is no need to search SDK caches or create a MoonBit project.

## Paragraph Justification

Enable paragraph justification unless the user explicitly declines it:

```typst
#set par(justify: true)
```

## Page Numbering

When page numbers are needed, use Typst's automatic page numbering instead of hardcoding them. For example, to display the current page and total page count in a "1 / 3" style at the bottom right:

```typst
#set page(numbering: "1 / 1", number-align: right + bottom)
```

## Finding Local Fonts

When you need to set a specific font in a Typst document, you can list the fonts available on the device in a way like the following (using Simplified Chinese SC as an example):

```
@shell.Pipeline([@shell.Cmd("typst", ["fonts"]), @shell.Cmd("rg", ["SC"])]).output()
```
