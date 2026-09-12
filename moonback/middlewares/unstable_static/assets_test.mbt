///|
async fn request_assets(
  middleware : @moonback.Middleware,
  path : String,
  meth? : @http.RequestMethod = Get,
  routes? : @moonback.Module = Module(_ctx => ()),
) -> (@http.Response, Bytes) {
  let app = @moonback.App(
    Module(ctx => {
      ctx.add_middleware(middleware)
      (routes.0)(ctx)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let listener = @moonback.listen(port=0)
    let task = group.spawn(() => app.serve(listener))
    defer task.cancel()
    let (response, body) = @http.request(
      "http://127.0.0.1:\{listener.addr.port()}\{path}",
      meth,
      {},
      b"",
    )
    (response, body.binary())
  })
}

///|
async test "embedded resources preserve bytes, content types, and HEAD length" {
  for
    (path, content, mime) in [
      (
        "/index.js", b"console.log('embedded')", "text/javascript; charset=utf-8",
      ),
      ("/image.png", b"\x89PNG\x00\xff", "image/png"),
      ("/font.woff2", b"wOF2\x00\xff", "font/woff2"),
      ("/empty.bin", b"", "application/octet-stream"),
    ] {
    let middleware = @unstable_static.from_assets(Map([(path, content)]))
    let (response, body) = request_assets(middleware, path)
    @test.assert_eq(response.code, 200)
    @test.assert_eq(body, content)
    @test.assert_eq(response.headers.get("content-type"), Some(mime))
    @test.assert_eq(
      response.headers.get("content-length"),
      Some(content.length().to_string()),
    )
    let (head, body) = request_assets(middleware, path, meth=Head)
    @test.assert_eq(head.code, 200)
    @test.assert_eq(
      head.headers.get("content-length"),
      Some(content.length().to_string()),
    )
    @test.assert_eq(body, b"")
  }
}

///|
async test "embedded directories and history fallback match filesystem semantics" {
  let files : Map[String, Bytes] = {
    "/index.html": b"home",
    "/docs/index.html": b"docs",
  }
  let middleware = @unstable_static.from_assets(
    files,
    rewrite_trailing_slash_index=true,
    history_fallback=Some("/index.html"),
  )
  for
    (path, expected) in [
      ("/", b"home"),
      ("/docs/", b"docs"),
      ("/dashboard", b"home"),
    ] {
    let (response, body) = request_assets(middleware, path)
    @test.assert_eq(response.code, 200)
    @test.assert_eq(body, expected)
  }
  let (response, _) = request_assets(
    @unstable_static.from_assets(files),
    "/docs/",
  )
  @test.assert_eq(response.code, 404)
  let (response, _) = request_assets(middleware, "/missing.js")
  @test.assert_eq(response.code, 404)
  let (response, body) = request_assets(middleware, "/dashboard", meth=Head)
  @test.assert_eq(response.code, 200)
  @test.assert_eq(body, b"")
  let (response, _) = request_assets(
    @unstable_static.from_assets(files, history_fallback=Some("/missing.html")),
    "/dashboard",
  )
  @test.assert_eq(response.code, 404)
}

///|
async test "embedded middleware preserves routes and falls back only on 404" {
  let middleware = @unstable_static.from_assets(
    { "/index.html": b"home", "/app.js": b"asset" },
    history_fallback=Some("/index.html"),
  )
  let routes = @moonback.Module(ctx => {
    ctx.get("/api", (_req, res) => res.send_text("API"))
    ctx.get("/dashboard", (_req, res) => res.send_void(status=404))
    ctx.post("/app.js", (_req, res) => res.send_text("POST"))
  })
  for
    (path, meth, expected) in [
      ("/api", @http.Get, b"API"),
      ("/dashboard", Get, b"home"),
      ("/app.js", Post, b"POST"),
    ] {
    let (response, body) = request_assets(middleware, path, meth~, routes~)
    @test.assert_eq(response.code, 200)
    @test.assert_eq(body, expected)
  }
}

///|
async test "embedded URLs decode once and reject malformed or traversing paths" {
  let middleware = @unstable_static.from_assets(
    {
      "/兔 +%.txt": b"unicode",
      "/%2e%2e.txt": b"literal",
      "/index.html": b"home",
    },
    history_fallback=Some("/index.html"),
  )
  for
    (path, expected) in [
      ("/%E5%85%94%20+%25.txt?v=1", b"unicode"),
      ("/%252e%252e.txt", b"literal"),
    ] {
    let (response, body) = request_assets(middleware, path)
    @test.assert_eq(response.code, 200)
    @test.assert_eq(body, expected)
  }
  for
    path in [
      "/%2e%2e/index.html", "/../index.html", "/%00", "/%5cindex.html", "/%ff", "/%",
      "/%0", "/%gg",
    ] {
    let (response, _) = request_assets(middleware, path)
    @test.assert_eq(response.code, 404)
  }
  let (response, _) = request_assets(
    @unstable_static.new(root="middlewares/unstable_static/testdata"),
    "/app%2ejs",
  )
  @test.assert_eq(response.code, 200)
}

///|
async test "embedded middleware snapshots the asset map" {
  let files : Map[String, Bytes] = { "/app.js": b"original" }
  let middleware = @unstable_static.from_assets(files)
  files["/app.js"] = b"changed"
  let (_, body) = request_assets(middleware, "/app.js")
  @test.assert_eq(body, b"original")
}
