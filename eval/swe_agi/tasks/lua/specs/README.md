# Lua 5.4 Spec Sources

This folder captures the Lua sources used by the `lua` test suite.

## Sources

All spec details are derived from the Lua 5.4 reference materials at:

- https://github.com/lua/lua/tree/v5.4
- https://www.lua.org/manual/5.4/

Copied source files:

- `manual/manual.of` (Lua 5.4.8 Reference Manual)

Additional provenance for test cases:

- Official Lua test suite under `testes/` in the same source tree
- https://www.lua.org/ftp/

## Normative vs. Informative

- Normative: the Lua 5.4.8 reference manual (`manual.of`).
- Informative/de-facto: the Lua `testes/` suite used for behavioral examples.

## Version

This suite targets Lua 5.4.8 (from `lua.h`).

## License

Lua is distributed under the Lua license (MIT-style). The license text is
included at the end of `lua.h` in the source tree.
