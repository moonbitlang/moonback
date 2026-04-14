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
async test "request_id reuses incoming header when trust_proxy is enabled" {
  let generator_calls : Ref[Int] = Ref::new(0)
  let handler = new(generator=() => {
    generator_calls.val = generator_calls.val + 1
    "generated-\{generator_calls.val}"
  })({ ..@moonback.Config::default(), trust_proxy: true }, (req, w) => {
    guard get(req) is Some(request_id) else {
      fail("expected request id in request context")
    }
    w.write_head(200, headers={ "Content-Type": "text/plain" })
    w.write(request_id)
  })

  let writer = run_handler(handler, Get, "/users", { "X-Request-ID": "req-123" })
  assert_eq(writer.code, Some(200))
  assert_eq(writer.headers.get("X-Request-ID"), Some("req-123"))
  assert_eq(writer.headers.get("Content-Type"), Some("text/plain"))
  assert_eq(writer.body.to_string(), "req-123")
  assert_eq(generator_calls.val, 0)
}

///|
async test "request_id ignores incoming header when trust_proxy is disabled" {
  let generator_calls : Ref[Int] = Ref::new(0)
  let handler = new(generator=() => {
    generator_calls.val = generator_calls.val + 1
    "generated-\{generator_calls.val}"
  })(@moonback.Config::default(), (req, w) => {
    guard get(req) is Some(request_id) else {
      fail("expected generated request id in request context")
    }
    w.write_head(200)
    w.write(request_id)
  })

  let writer = run_handler(handler, Get, "/users", { "X-Request-ID": "req-123" })
  assert_eq(writer.code, Some(200))
  assert_eq(writer.headers.get("X-Request-ID"), Some("generated-1"))
  assert_eq(writer.body.to_string(), "generated-1")
  assert_eq(generator_calls.val, 1)
}

///|
async test "request_id generates a new id when the request header is missing" {
  let generator_calls : Ref[Int] = Ref::new(0)
  let handler = new(generator=() => {
    generator_calls.val = generator_calls.val + 1
    "generated-\{generator_calls.val}"
  })(@moonback.Config::default(), (req, w) => {
    guard get(req) is Some(request_id) else {
      fail("expected generated request id in request context")
    }
    w.write_head(200)
    w.write(request_id)
  })

  let writer = run_handler(handler, Get, "/users", {})
  assert_eq(writer.code, Some(200))
  assert_eq(writer.headers.get("X-Request-ID"), Some("generated-1"))
  assert_eq(writer.body.to_string(), "generated-1")
  assert_eq(generator_calls.val, 1)
}

///|
async test "request_id can disable response headers while still setting context" {
  let generator_calls : Ref[Int] = Ref::new(0)
  let handler = new(
    generator=() => {
      generator_calls.val = generator_calls.val + 1
      "internal-\{generator_calls.val}"
    },
    header=None,
  )(@moonback.Config::default(), (req, w) => {
    guard get(req) is Some(request_id) else {
      fail("expected request id in request context")
    }
    w.write_head(200, headers={ "Content-Type": "text/plain" })
    w.write(request_id)
  })

  let writer = run_handler(handler, Get, "/users", {
    "X-Request-ID": "client-sent-id",
  })
  assert_eq(writer.code, Some(200))
  assert_true(writer.headers.get("X-Request-ID") is None)
  assert_eq(writer.headers.get("Content-Type"), Some("text/plain"))
  assert_eq(writer.body.to_string(), "internal-1")
  assert_eq(generator_calls.val, 1)
}
