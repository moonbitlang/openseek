# XML

A streaming XML parser for MoonBit, inspired by [quick-xml](https://github.com/tafia/quick-xml).

## Features

- **Pull-parser model** - Read XML events one at a time (like StAX in Java)
- **Streaming** - Memory-efficient processing of large documents
- **Multi-backend** - Works on wasm, wasm-gc, js, and native
- **XML 1.0 + Namespaces 1.0** - Full Unicode name character support

## Usage

```moonbit check
///|
test "basic parsing" {
  let xml = "<root><item id=\"1\">Hello</item></root>"
  let reader = @xml.Reader::from_string(xml)
  let event = reader.read_event()
  inspect(event.to_string(), content="Start({name: \"root\", attributes: []})")
}
```

## Reader API

### Read from string

```moonbit check
///|
test "read from string" {
  let xml = "<root>Hello</root>"
  let reader = @xml.Reader::from_string(xml)
  let event = reader.read_event()
  inspect(event.to_string(), content="Start({name: \"root\", attributes: []})")
}
```

### Read all events

```moonbit check
///|
test "basic writing" {
  let writer = @xml.Writer::new()
  writer.start_element("root", [])
  writer.text("Hello")
  writer.end_element("root")
  let xml = writer.to_string()
  inspect(xml, content="<root>Hello</root>")
}
```

### Write with attributes

```moonbit check
///|
test "write with attributes" {
  let writer = @xml.Writer::new()
  writer.empty_element("item", [("id", "1"), ("class", "active")])
  let xml = writer.to_string()
  inspect(xml, content="<item id=\"1\" class=\"active\"/>")
}
```

### Write CDATA

```moonbit check
///|
test "write cdata" {
  let writer = @xml.Writer::new()
  writer.start_element("root", [])
  writer.cdata("<special>content</special>")
  writer.end_element("root")
  let xml = writer.to_string()
  inspect(xml, content="<root><![CDATA[<special>content</special>]]></root>")
}
```

### Write comment

```moonbit check
///|
test "write comment" {
  let writer = @xml.Writer::new()
  writer.comment("This is a comment")
  writer.empty_element("root", [])
  let xml = writer.to_string()
  inspect(xml, content="<!--This is a comment--><root/>")
}
```

## Escape/Unescape

```moonbit check
///|
test "escape text" {
  let text = "<script>alert('XSS')</script>"
  let escaped = @xml.escape(text)
  inspect(escaped, content="&lt;script&gt;alert('XSS')&lt;/script&gt;")
}
```

```moonbit check
///|
test "unescape entities" {
  let text = "&lt;tag&gt; &amp; &quot;quoted&quot; &apos;apos&apos;"
  let unescaped = @xml.unescape(text)
  inspect(unescaped, content="<tag> & \"quoted\" 'apos'")
}
```

## Limitations

- **Non-validating** - Does not validate against DTD
- **UTF-8 only** - Other encodings not supported
- **XML 1.0 only** - XML 1.1 not supported
