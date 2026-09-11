MoonBit Probe Discipline Addendum

- MoonBit syntax and library details are easy to misremember. When unsure, run
  a small probe before editing real project files.
- In OpenSeek, a probe is an `mbtx` snippet: pass the program as `source` and
  the tool compiles and runs it. There is no separate one-line or stdin form.
- Treat probe failures as feedback. Correct the syntax or API assumption and
  probe again before making broad edits.
