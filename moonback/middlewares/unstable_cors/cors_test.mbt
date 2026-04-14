///|
struct TestWriter {
  mut code : Int?
  mut headers : Map[String, String]
  body : StringBuilder
}

///|
fn TestWriter::new() -> TestWriter {
  { code: None, headers: {}, body: StringBuilder::new() }
}

///|
pub impl @io.Writer for TestWriter with write_once(self, buf, offset~, len~) {
  self.body.write_string(@utf8.decode(buf[offset:offset + len]))
  len
}

///|
pub impl @moonback.ResponseWriter for TestWriter with write_head(
  self,
  code,
  headers?,
) {
  self.code = Some(code)
  self.headers = match headers {
    Some(headers) => headers
    None => {}
  }
}

///|
pub impl @moonback.ResponseWriter for TestWriter with flush(_self) {

}

///|
async fn run_handler(
  handler : @moonback.Handler,
  meth : @http.RequestMethod,
  path : String,
  headers : Map[String, String],
) -> TestWriter {
  let (body, sink) = @io.pipe()
  sink.close()
  defer body.close()
  let writer = TestWriter::new()
  handler({ ctx: @moonback.mock_context, meth, path, headers, body }, writer)
  writer
}

///|
async test "cors adds default headers to normal requests with origin" {
  let handler = new()(@moonback.Config::default(), (_r, w) => {
    w.write_head(200, headers={ "Content-Type": "text/plain" })
    w.write("ok")
  })

  let writer = run_handler(handler, Get, "/users", {
    "Origin": "https://app.example.com",
  })
  assert_eq(writer.code, Some(200))
  assert_eq(writer.headers.get("Access-Control-Allow-Origin"), Some("*"))
  assert_eq(writer.headers.get("Content-Type"), Some("text/plain"))
  assert_eq(writer.body.to_string(), "ok")
}

///|
async test "cors skips requests without origin" {
  let handler = new()(@moonback.Config::default(), (_r, w) => {
    w.write_head(200, headers={ "X-Test": "1" })
  })

  let writer = run_handler(handler, Get, "/users", {})
  assert_eq(writer.code, Some(200))
  assert_true(writer.headers.get("Access-Control-Allow-Origin") is None)
  assert_eq(writer.headers.get("X-Test"), Some("1"))
}

///|
async test "cors handles preflight requests without calling next" {
  let handler = new()(@moonback.Config::default(), (_r, w) => {
    w.write_head(418)
    w.write("should not run")
  })

  let writer = run_handler(handler, Options, "/users", {
    "Origin": "https://app.example.com",
    "Access-Control-Request-Method": "PATCH",
    "Access-Control-Request-Headers": "Authorization, X-Trace-ID",
  })
  assert_eq(writer.code, Some(204))
  assert_eq(writer.headers.get("Access-Control-Allow-Origin"), Some("*"))
  assert_eq(
    writer.headers.get("Access-Control-Allow-Methods"),
    Some("GET, POST, PUT, PATCH, DELETE, OPTIONS"),
  )
  assert_eq(
    writer.headers.get("Access-Control-Allow-Headers"),
    Some("Authorization, X-Trace-ID"),
  )
  assert_eq(writer.headers.get("Vary"), Some("Access-Control-Request-Headers"))
  assert_eq(writer.body.to_string(), "")
}

///|
async test "cors can reflect origin when credentials are enabled" {
  let handler = new(
    allow_credentials=true,
    expose_headers=Some("X-Request-ID"),
    max_age=Some(600),
  )(@moonback.Config::default(), (_r, w) => w.write_head(200))

  let writer = run_handler(handler, Get, "/users", {
    "Origin": "https://app.example.com",
  })
  assert_eq(
    writer.headers.get("Access-Control-Allow-Origin"),
    Some("https://app.example.com"),
  )
  assert_eq(
    writer.headers.get("Access-Control-Allow-Credentials"),
    Some("true"),
  )
  assert_eq(
    writer.headers.get("Access-Control-Expose-Headers"),
    Some("X-Request-ID"),
  )
  assert_eq(writer.headers.get("Vary"), Some("Origin"))

  let preflight = run_handler(handler, Options, "/users", {
    "Origin": "https://app.example.com",
    "Access-Control-Request-Method": "GET",
  })
  assert_eq(preflight.code, Some(204))
  assert_eq(
    preflight.headers.get("Access-Control-Allow-Origin"),
    Some("https://app.example.com"),
  )
  assert_eq(
    preflight.headers.get("Access-Control-Allow-Credentials"),
    Some("true"),
  )
  assert_eq(preflight.headers.get("Access-Control-Max-Age"), Some("600"))
  assert_eq(preflight.headers.get("Vary"), Some("Origin"))
}
