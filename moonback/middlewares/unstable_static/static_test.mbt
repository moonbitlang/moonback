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
fn fallback_handler(name : String) -> @moonback.Handler {
  (_, w) => {
    w.write_head(404, headers={ "X-Fallback": name })
    w.write("fallback:\{name}")
  }
}

///|
async test "serve serves index file for root path" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="moonback-serve-root")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    @fs.write_file("\{root}/index.html", "hello", create=0o644)

    let writer = run_handler(
      new(root)(@moonback.Config::default(), fallback_handler("root")),
      Get,
      "/",
    )
    assert_eq(writer.code, Some(200))
    assert_eq(
      writer.headers.get("Content-Type"),
      Some("text/html; charset=utf-8"),
    )
    assert_eq(writer.body.to_string(), "hello")
  })
}

///|
async test "serve strips query string and serves nested file" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="moonback-serve-query")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    @fs.mkdir("\{root}/assets", permission=0o755)
    @fs.write_file("\{root}/assets/app.css", "body{}", create=0o644)

    let writer = run_handler(
      new(root, history_fallback=true)(
        @moonback.Config::default(),
        fallback_handler("query"),
      ),
      Get,
      "/assets/app.css?v=1",
    )
    assert_eq(writer.code, Some(200))
    assert_eq(
      writer.headers.get("Content-Type"),
      Some("text/css; charset=utf-8"),
    )
    assert_eq(writer.body.to_string(), "body{}")
  })
}

///|
async test "serve can disable directory index" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="moonback-serve-no-index")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    @fs.write_file("\{root}/index.html", "hello", create=0o644)

    let writer = run_handler(
      new(root, directory_index=false)(
        @moonback.Config::default(),
        fallback_handler("no-index"),
      ),
      Get,
      "/",
    )
    assert_eq(writer.code, Some(404))
    assert_eq(writer.headers.get("X-Fallback"), Some("no-index"))
    assert_eq(writer.body.to_string(), "fallback:no-index")
  })
}

///|
async test "serve supports history fallback for spa routes" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="moonback-serve-history")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    @fs.write_file("\{root}/index.html", "spa", create=0o644)

    let writer = run_handler(
      new(root, history_fallback=true)(
        @moonback.Config::default(),
        fallback_handler("history"),
      ),
      Get,
      "/dashboard/settings",
    )
    assert_eq(writer.code, Some(200))
    assert_eq(writer.body.to_string(), "spa")
  })
}

///|
async test "serve does not fallback when downstream handler returns non-404" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="moonback-serve-history-ok")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    @fs.write_file("\{root}/index.html", "spa", create=0o644)
    let handler = new(root, history_fallback=true)(
      @moonback.Config::default(),
      (_r, w) => {
        w.write_head(200, headers={ "Content-Type": "application/json" })
        w.write("{\"message\":\"pong\"}")
      },
    )

    let writer = run_handler(handler, Get, "/api/ping")
    assert_eq(writer.code, Some(200))
    assert_eq(writer.headers.get("Content-Type"), Some("application/json"))
    assert_eq(writer.body.to_string(), "{\"message\":\"pong\"}")
  })
}

///|
async test "serve does not history-fallback asset requests" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="moonback-serve-asset-miss")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    @fs.write_file("\{root}/index.html", "spa", create=0o644)

    let writer = run_handler(
      new(root, history_fallback=true)(
        @moonback.Config::default(),
        fallback_handler("asset-miss"),
      ),
      Get,
      "/assets/app.js",
    )
    assert_eq(writer.code, Some(404))
    assert_eq(writer.headers.get("X-Fallback"), Some("asset-miss"))
    assert_eq(writer.body.to_string(), "fallback:asset-miss")
  })
}

///|
async test "serve falls through for missing files and non-get requests" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="moonback-serve-fallback")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    let handler = new(root)(
      @moonback.Config::default(),
      fallback_handler("miss"),
    )

    let missing = run_handler(handler, Get, "/missing.txt")
    assert_eq(missing.code, Some(404))
    assert_eq(missing.headers.get("X-Fallback"), Some("miss"))
    assert_eq(missing.body.to_string(), "fallback:miss")

    let post = run_handler(handler, Post, "/missing.txt")
    assert_eq(post.code, Some(404))
    assert_eq(post.headers.get("X-Fallback"), Some("miss"))
    assert_eq(post.body.to_string(), "fallback:miss")
  })
}
