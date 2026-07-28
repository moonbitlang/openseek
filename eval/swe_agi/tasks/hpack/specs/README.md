# HPACK Specification

## Primary Reference

**RFC 7541 - HPACK: Header Compression for HTTP/2**
- https://tools.ietf.org/html/rfc7541

## Sections

1. **Introduction** - Overview of HPACK
2. **Compression Process Overview** - How compression works
3. **Header Field Representation** - Binary format
4. **Dynamic Table Management** - Entry addition/eviction
5. **Primitive Type Representations** - Integers and strings
6. **Binary Format** - Detailed encoding rules
7. **Security Considerations** - CRIME, memory limits

## Key Concepts

### Static Table (Appendix A)
61 predefined header field entries covering common HTTP headers.

### Dynamic Table
FIFO queue of recently used header fields, configurable size.

### Huffman Coding (Appendix B)
257-entry symbol table for string compression.

## Test Vectors

Compatibility test cases from multiple implementations:
- https://github.com/http2jp/hpack-test-case

Implementations covered:
- Go (go-hpack)
- C (nghttp2)
- Python (python-hpack)
- Node.js (node-http2-hpack)
- Haskell (haskell-http2)
- Swift (swift-nio-hpack)

## License

RFC 7541 is published by the IETF and is freely available.
Test vectors are from the hpack-test-case repository (MIT License).
