# Typst Syntax Cautions

When answering questions about Typst's math syntax, keep the following cautions in mind and never repeat the mistakes they describe.

## Caution 0 - Fetch the official reference instead of guessing

When unsure about any Typst detail (element syntax, function arguments, symbol names), do not guess: fetch the official documentation and treat it as the source of truth.

- Markup / model elements: https://typst.app/docs/reference/model/
- Math: https://typst.app/docs/reference/math/
- Symbol table: https://typst.app/docs/reference/symbols/sym/

## Caution 1 - Do not treat operator characters as literal text

In Typst math mode, many ASCII characters that "look printable" are actually operators or shorthands with special meaning. Before treating a symbol as a literal character, check whether Typst gives it a defined role; if so, use a character escape or quoted text to produce the literal character.

Example: `/` is the fraction operator, so `1/2` produces a stacked fraction, equivalent to `frac(1, 2)`. To display a literal slash, use `\/` or `"/"`.

```typst
$1/2$        // stacked fraction
$frac(1, 2)$ // same as above (stacked)
$1 \/ 2$     // a literal slash 1/2
$1 "/" 2$    // a literal slash using quoted text
```

## Caution 2 - Do not invent directive or keyword syntax

Typst math functions use function-call syntax rather than TeX's `\command` syntax. Typst also has dedicated syntax, such as `_` and `^` for attachments, and code keywords such as `set` and `show` for styling. Check the [official syntax reference](https://typst.app/docs/reference/syntax/) instead of assuming that every rendering change is an ordinary function call or inventing keywords.

Example: [`limits`](https://typst.app/docs/reference/math/attach/#functions-limits) is a function, not a modifier token. Call it on the base to place its bottom and top attachments below and above the base instead of beside it.

```typst
$limits(A)_1^2 != A_1^2$
```

## Caution 3 - Understand repeated alignment markers

Each `&` marks one alignment point. Multiple alignment points create alternating right- and left-aligned columns. `&&` is valid: it represents two consecutive alignment points and has the same alignment behavior as `& &`, as documented in the [official alignment reference](https://typst.app/docs/reference/math/#alignment).

Example: the first `&` aligns the equations at `=`, and the following `&&` makes the annotation column left-aligned.

```typst
$
  a &= b && "first equation" \
  c &= d && "second equation"
$
```

Do not infer the meaning or validity of other repeated markers from this example; verify each construct against its documented syntax.

## Caution 4 - Do not use TeX macros for symbols or functions

Typst symbol and function names never begin with a backslash (`\`). Do not write TeX macros such as `\dots` or `\cdots`. Use `dots` for a baseline ellipsis (`…`) and `dots.c` for a centered ellipsis (`⋯`). Backslashes still have documented uses, such as character escapes and line breaks; they do not introduce symbol or function names.

```typst
$dots$   // … (baseline ellipsis)
$dots.c$ // ⋯ (centered ellipsis)
```

For other symbols you are unsure about, validate a code snippet with a command such as `typst eval '$dots$'`, or consult the [official symbol table](https://typst.app/docs/reference/symbols/sym/).
