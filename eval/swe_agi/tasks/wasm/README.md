# WebAssembly (WASM)

A WebAssembly **binary module decoder** and **validator** for MoonBit.

This package is designed for:
- Decoding `.wasm` bytes into a structured `Module`
- Validating the decoded module according to the WebAssembly spec
- Printing the module in WebAssembly text format

## API

- `decode_module(data : Bytes) -> Module raise DecodeError`
- `validate_module(mod_ : Module) -> Unit raise ValidationError`
- `Module::print(self : Module) -> String`

## Basic usage

Decode and validate a module:

```moonbit check

///|
test "decode and validate" {
  let bytes : Bytes = b"\x00asm\x01\x00\x00\x00" // empty module
  let m = @wasm.decode_module(bytes)
  @wasm.validate_module(m)
}
```

Print a module:

```moonbit check

///|
test "print" {
  let bytes : Bytes = b"\x00asm\x01\x00\x00\x00"
  let m = @wasm.decode_module(bytes)
  let wat = m.print()
  inspect(wat.length() > 0, content="true")
}
```

Handle malformed and invalid inputs:

```moonbit check

///|
test "errors" {
  // Malformed: not a WebAssembly binary
  try @wasm.decode_module(b"not wasm") catch {
    e => inspect(e.to_string().length() > 0, content="true")
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}
```

## Output compatibility

`Module::print()` is expected to be compatible with `wasm-tools print` (the same canonical text format).

## Development

This repository directory is also a spec-driven test suite.
Implementation/generator details live in `wasm/TASK.md`.

## References

- WebAssembly Core Specification: <https://webassembly.github.io/spec/core/>
- wasm-tools: <https://github.com/bytecodealliance/wasm-tools>
