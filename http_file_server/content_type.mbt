///|
/// Static HTTP resources use the requested filename, without sniffing or
/// decoding content. Shared by embedded hosts and the CLI.
pub fn content_type(name : String) -> String {
  let extension = match name.rev_split_once(".") {
    Some((_, extension)) => extension.to_owned().to_lower()
    None => ""
  }
  match extension {
    "html" | "htm" => "text/html; charset=utf-8"
    "js" | "mjs" => "text/javascript; charset=utf-8"
    "css" => "text/css; charset=utf-8"
    "json" | "map" => "application/json"
    "svg" => "image/svg+xml"
    "png" => "image/png"
    "apng" => "image/apng"
    "jpg" | "jpeg" => "image/jpeg"
    "gif" => "image/gif"
    "webp" => "image/webp"
    "avif" => "image/avif"
    "bmp" => "image/bmp"
    "tif" | "tiff" => "image/tiff"
    "ico" => "image/x-icon"
    "ttf" => "font/ttf"
    "otf" => "font/otf"
    "woff" => "font/woff"
    "woff2" => "font/woff2"
    "wasm" => "application/wasm"
    "txt" | "md" => "text/plain; charset=utf-8"
    "csv" => "text/csv; charset=utf-8"
    "xml" => "application/xml"
    "pdf" => "application/pdf"
    "mp3" => "audio/mpeg"
    "mp4" => "video/mp4"
    "webm" => "video/webm"
    _ => "application/octet-stream"
  }
}
