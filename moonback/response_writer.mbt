///|
pub(open) trait ResponseWriter: @io.Writer {
  async write_head(self : Self, code : Int, headers? : Map[String, String]) -> Unit
  async flush(self : Self) -> Unit
  async with_headers(Self, (Headers) -> Unit) -> &ResponseWriter = _
}

///|
priv struct WithHeaders {
  inner : &ResponseWriter
  header_fn : Array[(Headers) -> Unit]
}

///|
pub impl ResponseWriter for @http.ServerConnection with write_head(
  self,
  code,
  headers?,
) {
  self.send_response(
    code,
    status_code_to_reason_phrase(code),
    extra_headers?=headers,
  )
}

///|
pub impl ResponseWriter for @http.ServerConnection with flush(self) {
  self.flush()
}

///|
impl ResponseWriter with with_headers(self, header_fn : (Headers) -> Unit) -> &ResponseWriter {
  WithHeaders::{ inner: self, header_fn: [header_fn] }
}

///|
impl ResponseWriter for WithHeaders with with_headers(self, header_fn) -> &ResponseWriter {
  self.header_fn.push(header_fn)
  self
}

///|
impl @io.Writer for WithHeaders with write_once(self, buf, offset~, len~) {
  self.inner.write_once(buf, offset~, len~)
}

///|
impl ResponseWriter for WithHeaders with write_head(self, code, headers?) {
  let headers = Headers(raw?=headers)
  for header_fn in self.header_fn.rev_iter() {
    header_fn(headers)
  }
  self.inner.write_head(code, headers=headers.repr())
}

///|
impl ResponseWriter for WithHeaders with flush(self) {
  self.inner.flush()
}

///|
pub async fn &ResponseWriter::text(
  self : &ResponseWriter,
  code? : Int = 200,
  data : String,
) -> Unit {
  self.write_head(code, headers={ "Content-Type": "text/plain" })
  self.write(data)
  raise StopResponding
}

///|
pub async fn &ResponseWriter::json(
  self : &ResponseWriter,
  code? : Int = 200,
  data : Json,
) -> Unit {
  self.write_head(code, headers={ "Content-Type": "application/json" })
  self.write(data.stringify())
  raise StopResponding
}

///|
pub async fn &ResponseWriter::blob(
  self : &ResponseWriter,
  code? : Int = 200,
  mime? : String = "application/octet-stream",
  size? : Int,
  body : &@io.Reader,
) -> Unit {
  self.write_head(
    code,
    headers=if size is Some(size) {
      { "Content-Type": mime, "Content-Length": size.to_string() }
    } else {
      { "Content-Type": mime }
    },
  )
  self.write_reader(body)
  raise StopResponding
}
