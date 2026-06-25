# `@output` — bounded tool output

Internal helpers shared by the agent's `moon`-running tools (`moon_cmd`, …) to
keep a tool result within a caller-supplied size budget and to tell the model,
in-band, when output was clipped.

A tool renders its result as an optional **truncation header** followed by the
**capped body**:

```
<truncation_header(body, max)>
<cap_text(body, max)>
```

so the model sees a banner describing what was dropped before reading the
(possibly shortened) text. All three functions measure length in UTF-16 code
units, matching MoonBit's `String::length`.

## `cap_text` — keep at most `max_chars`

Returns the content unchanged when it already fits, otherwise keeps the leading
`max_chars` code units:

```mbt check
///|
test "cap_text keeps short text and clips long text" {
  inspect(@output.cap_text("ok", 8), content="ok")
  inspect(@output.cap_text("hello, world", 5), content="hello")
}
```

A character that needs two code units (a surrogate pair, such as an emoji) is
never split: if the budget lands inside the pair the whole character is dropped,
so the kept prefix is always valid text:

```mbt check
///|
test "cap_text does not split a surrogate pair" {
  // "😀" is two UTF-16 code units; a budget of 1 keeps nothing, 2 keeps it whole.
  inspect(@output.cap_text("😀x", 1), content="")
  inspect(@output.cap_text("😀x", 2), content="😀")
}
```

## `is_truncated` — would `cap_text` drop anything?

The predicate behind the header. It is `true` exactly when the content is longer
than the budget:

```mbt check
///|
test "is_truncated compares length against the budget" {
  inspect(@output.is_truncated("hello, world", 5), content="true")
  inspect(@output.is_truncated("ok", 8), content="false")
  // The boundary fits: length == budget is not truncation.
  inspect(@output.is_truncated("hello", 5), content="false")
}
```

## `truncation_header` — describe what was dropped

When (and only when) the content is truncated, this renders a metadata block —
a leading newline plus `truncated`/`output_chars`/`shown_chars` lines reporting
the original and shown sizes. It is the empty string when nothing was dropped,
so a tool can always concatenate it unconditionally:

```mbt check
///|
test "truncation_header reports sizes, or is empty when it fits" {
  inspect(
    @output.truncation_header("hello, world", 5),
    content=(
      #|
      #|truncated=true
      #|output_chars=12
      #|shown_chars=5
    ),
  )
  inspect(@output.truncation_header("ok", 8), content="")
}
```

## Putting it together

How a tool composes a bounded result — header first, then the capped body:

```mbt check
///|
test "compose a bounded tool result" {
  let body = "abcdefghij"
  let max = 4
  let rendered = @output.truncation_header(body, max) +
    "\n" +
    @output.cap_text(body, max)
  inspect(
    rendered,
    content=(
      #|
      #|truncated=true
      #|output_chars=10
      #|shown_chars=4
      #|abcd
    ),
  )
}
```
