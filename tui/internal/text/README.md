# bobzhang/openseek/tui/internal/text

This package owns the TUI's input sanitization policy.

Display-width measurement, truncation, hard-line splitting, and cursor-safe
views live in `moonbit-community/displaytext`; this package only normalizes raw
text before it is echoed back to the terminal.

## Usage

```mbt
@text.sanitize("a\u{1b}[31m")  // "a[31m"
@text.sanitize("a\rb")         // "a\nb"
@text.sanitize("ab\tc")        // "ab      c"
```

`sanitize` drops C0 controls and DEL, normalizes carriage returns to `\n`, and
expands tabs to the next 8-column stop.

Internal to `tui/` — only importable within the module.
