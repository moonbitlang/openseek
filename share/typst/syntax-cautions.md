# Typst Syntax Cautions

When answering questions about Typst's math syntax, keep the following cautions in mind and never repeat the mistakes they describe.

## Caution 0 - Fetch the official reference instead of guessing

When unsure about any Typst detail (element syntax, function arguments, symbol names), do not guess: fetch the official documentation and treat it as the source of truth.

- Markup / model elements: https://typst.app/docs/reference/model/
- Math: https://typst.app/docs/reference/math/
- Symbol table: https://typst.app/docs/reference/symbols/sym/

## Caution 1 - Do not treat operator characters as literal text

In Typst math mode, many ASCII characters that "look printable" are actually operators or shorthands with special meaning. Before treating a symbol as a literal character, check whether Typst gives it a defined role; if so, it renders as that construct, and producing the literal character requires escaping.

Example: `/` is the fraction operator, so `1/2` is a real stacked fraction, exactly the same as `frac(1, 2)` and TeX's `\frac`. It is NOT a slanted slash.

```typst
$ 1/2 $        // same as \frac{1}{2} (stacked)
$ frac(1, 2) $ // same as above (stacked)
$ 1 \/ 2 $     // a literal slash 1/2
```

## Caution 2 - Do not invent directive or keyword syntax

Typst has no LaTeX-style keyword/directive syntax. Anything that changes rendering is just a normal function call with ordinary arguments. Do not invent special keywords, option words, or `\command`-like forms.

Example: `limits` is an ordinary function, not a modifier token. You call it on the expression you want to affect; it changes where sub/superscripts sit.

```typst
$ limits(A)_1^2 != A_1^2 $
```

## Caution 3 - Do not invent compound delimiters

Alignment and similar markers are written with a single delimiter. Do not double or stack a delimiter and assume it creates extra structure (more columns, multiple groups, etc.) unless the official reference documents it.

Example: the alignment marker is a single `&`, as in TeX; there is no `&&`.

```typst
$
  a &= b \
  c &= d
$
```

More generally, when tempted to write a doubled marker (`&&`, `::`, `**`, and the like) as if it were a distinct construct, verify it against the reference first; otherwise use the single documented form.
