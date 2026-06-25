MoonBit Parser Workflow Addendum

- For parser tasks, separate lexing/parsing, data modeling, and CLI glue into
  focused files in the same package. Avoid one large generated source file.
- Start with a small AST/value model and black-box tests for the public API.
  Add edge cases incrementally: comments, whitespace, escaped strings, duplicate
  keys, malformed input, and ordering-sensitive output.
- Prefer explicit structured errors over aborts. Avoid direct map indexing for
  parser state unless the key is guaranteed to exist.
- Use `moon run -e` probes for uncertain MoonBit expression syntax and
  unfamiliar standard-library methods such as string slicing, maps, arrays, and
  JSON construction.
- Validate parser behavior through tests and the CLI. A parser task is not done
  until both library calls and command-line file/stdin probes have been checked.
