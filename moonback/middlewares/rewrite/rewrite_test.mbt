///|
struct TestWriter {
  mut code : Int?
  body : StringBuilder
}

///|
fn TestWriter::new() -> TestWriter {
  { code: None, body: StringBuilder::new() }
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
  ignore(headers)
  self.code = Some(code)
}

///|
pub impl @moonback.ResponseWriter for TestWriter with flush(_self) {

}

///|
fn capture_path_handler() -> @moonback.Handler {
  (r, w) => {
    w.write_head(200)
    w.write(r.path)
  }
}

///|
async fn run_handler(
  handler : @moonback.Handler,
  meth : @http.RequestMethod,
  path : String,
) -> TestWriter {
  let (body, sink) = @io.pipe()
  sink.close()
  defer body.close()
  let writer = TestWriter::new()
  handler(
    { ctx: @moonback.mock_context, meth, path, headers: {}, body },
    writer,
  )
  writer
}

///|
async test "rewrite rewrites exact matches and leaves misses unchanged" {
  let handler = new({ "/legacy": "/v2" })(
    @moonback.Config::default(),
    capture_path_handler(),
  )

  let rewritten = run_handler(handler, Get, "/legacy")
  assert_eq(rewritten.code, Some(200))
  assert_eq(rewritten.body.to_string(), "/v2")

  let passthrough = run_handler(handler, Get, "/current")
  assert_eq(passthrough.code, Some(200))
  assert_eq(passthrough.body.to_string(), "/current")
}

///|
async test "rewrite supports wildcard captures in replacements" {
  let handler = new({ "/blog/*": "/posts/$1" })(
    @moonback.Config::default(),
    capture_path_handler(),
  )

  let writer = run_handler(handler, Get, "/blog/guides/intro")
  assert_eq(writer.code, Some(200))
  assert_eq(writer.body.to_string(), "/posts/guides/intro")
}

///|
async test "rewrite supports multiple wildcard captures" {
  let handler = new({ "/assets/*/raw/*": "/cdn/$2/$1" })(
    @moonback.Config::default(),
    capture_path_handler(),
  )

  let writer = run_handler(handler, Get, "/assets/icons/raw/logo.svg")
  assert_eq(writer.code, Some(200))
  assert_eq(writer.body.to_string(), "/cdn/logo.svg/icons")
}

///|
async test "rewrite preserves query strings and fragments" {
  let handler = new({ "/docs/*": "/pages/$1" })(
    @moonback.Config::default(),
    capture_path_handler(),
  )

  let writer = run_handler(handler, Get, "/docs/api/reference?lang=en#top")
  assert_eq(writer.code, Some(200))
  assert_eq(writer.body.to_string(), "/pages/api/reference?lang=en#top")
}

///|
async test "rewrite evaluates rules in insertion order" {
  let rules : Map[String, String] = {}
  rules.set("/api/health", "/status")
  rules.set("/api/*", "/v1/$1")
  let handler = new(rules)(@moonback.Config::default(), capture_path_handler())

  let writer = run_handler(handler, Get, "/api/health")
  assert_eq(writer.code, Some(200))
  assert_eq(writer.body.to_string(), "/status")
}
