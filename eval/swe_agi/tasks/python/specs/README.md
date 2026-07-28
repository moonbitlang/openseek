## Sources (CPython)

This suite’s test cases are derived from CPython’s official regression tests:

- CPython v3.12.2:
  - `Lib/test/test_grammar.py`
  - `Lib/test/test_bool.py`

Upstream links (tagged):

- `test_grammar.py`: https://github.com/python/cpython/blob/v3.12.2/Lib/test/test_grammar.py
- `test_bool.py`: https://github.com/python/cpython/blob/v3.12.2/Lib/test/test_bool.py

##

## Notes

- This repository does **not** vendor the entire CPython test suite. Instead it
  includes a curated subset transcribed into MoonBit tests.
- Each translated MoonBit test block includes a short note indicating the
  originating CPython test module or section.

## License

CPython is distributed under the PSF License. See:

- https://docs.python.org/3/license.html
- https://github.com/python/cpython/blob/v3.12.2/LICENSE
