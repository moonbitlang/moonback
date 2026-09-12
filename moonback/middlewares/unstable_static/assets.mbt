///|
priv enum StaticSource {
  Directory(String)
  Assets(Map[String, Bytes])
}

///|
/// Serve embedded static files without reading the filesystem.
///
/// Keys are decoded absolute URL paths, such as `/index.html` and `/fonts/ui.woff2`.
/// The map is copied when the middleware is created. Missing resources fall
/// through to the next handler. GET/HEAD, directory indexes, and history fallback
/// follow the same rules as `new`.
pub fn from_assets(
  assets : Map[String, Bytes],
  rewrite_trailing_slash_index? : Bool = false,
  history_fallback? : String? = None,
) -> @moonback.Middleware {
  static_middleware(
    Assets(assets.copy()),
    rewrite_trailing_slash_index~,
    history_fallback~,
  )
}

///|
async fn resolve_static_resource(
  source : StaticSource,
  request_path : String,
  trailing_slash~ : Bool,
  rewrite_trailing_slash_index~ : Bool,
) -> ServedPath {
  match source {
    Directory(root) =>
      resolve_served_file(
        root,
        request_path,
        trailing_slash~,
        rewrite_trailing_slash_index~,
      )
    Assets(files) => {
      let path = "/" + request_path
      if files.get(path) is Some(content) {
        Content(path, content)
      } else if trailing_slash && rewrite_trailing_slash_index {
        let index = join_path(path, "index.html")
        files.get(index).map_or(Missing, content => Content(index, content))
      } else {
        Missing
      }
    }
  }
}

///|
async fn send_content(
  req : @moonback.Request,
  res : @moonback.Responder,
  path : String,
  content : Bytes,
) -> Unit {
  let headers = @moonback.Headers::from({
    "Content-Type": guess_content_type(path),
    "Content-Length": content.length().to_string(),
  })
  if req.meth is Head {
    res.send_void(status=200, headers~)
  } else {
    let writer = res.respond(status=200, headers~)
    writer.write(content)
  }
}

///|
fn hex_digit(byte : Byte) -> Int? {
  match byte.to_int() {
    n if n >= 48 && n <= 57 => Some(n - 48)
    n if n >= 65 && n <= 70 => Some(n - 65 + 10)
    n if n >= 97 && n <= 102 => Some(n - 97 + 10)
    _ => None
  }
}

///|
// Decode only request URLs, never configured asset keys or fallback paths.
fn decode_request_path(path : String) -> String? {
  guard path.contains("%") else { Some(path) }
  let bytes = @utf8.encode(path)
  let decoded = @buffer.Buffer()
  for i = 0 {
    guard i < bytes.length() else { break }
    if bytes[i] == b'%' {
      guard i + 2 < bytes.length() &&
        hex_digit(bytes[i + 1]) is Some(high) &&
        hex_digit(bytes[i + 2]) is Some(low) else {
        return None
      }
      decoded.write_byte((high * 16 + low).to_byte())
      continue i + 3
    } else {
      decoded.write_byte(bytes[i])
      continue i + 1
    }
  }
  try @utf8.decode(decoded.to_bytes(), ignore_bom=true) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}
