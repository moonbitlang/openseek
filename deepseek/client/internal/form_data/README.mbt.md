# Multipart Form Data

`moonbitlang/openseek/deepseek/client/internal/form_data` encodes text and binary file fields as
`multipart/form-data`. It owns boundary selection, quoted header parameters,
UTF-8 text encoding, field separators, and the final delimiter.

```mbt nocheck
///|
let form = @form_data.FormData([
  Text(name="purpose", value="user_data"),
  File(
    name="file",
    filename="photo.png",
    content_type="image/png",
    data=image_bytes,
  ),
])

///|
let connection = @http.post_stream(url, headers={
  "Content-Type": form.content_type(),
})

///|
form.write_to(connection)
```

Construction validates metadata and generates a boundary from 30 secure random
bytes encoded as 60 hexadecimal characters. It does not scan headers or field
contents for collisions; the random boundary makes accidental collisions
negligibly unlikely. If secure randomness is unavailable, construction raises
`FormDataError::EntropyUnavailable`.

A form must contain at least one field. Order and
duplicate names are preserved. Names must be nonempty; names and filenames may
contain Unicode, quotes, and backslashes, but no ASCII control characters. File
content types must be nonempty ASCII without control characters; callers supply
a valid MIME type. Failures are typed `FormDataError` variants.

The constructed form is immutable. Changing the original field array does not
change its body. Binary `Bytes` values are retained unchanged without another
full-body allocation. `write_to` accepts an `async/io.Writer`, writes sequentially,
and propagates write errors and cancellation. It does not flush or close the
writer, send HTTP headers, or finish an HTTP request; callers own those actions.

This package has no image-format, upload-size, expiry, authentication, retry,
or provider-response policy. The encoding follows
[RFC 7578](https://www.rfc-editor.org/rfc/rfc7578.html) and the multipart syntax in
[RFC 2046 section 5.1.1](https://www.rfc-editor.org/rfc/rfc2046.html#section-5.1.1).
