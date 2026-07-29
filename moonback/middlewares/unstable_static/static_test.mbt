///|
let fixture_root = "middlewares/unstable_static/testdata"

///|
async fn send_request(
  middleware : @moonback.Middleware,
  path : String,
  extra_routes? : @moonback.Module = Module(_ctx => ()),
) -> (Int, String?, String) {
  let app = @moonback.App(
    Module(ctx => {
      ctx.add_middleware(middleware)
      (extra_routes.0)(ctx)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = @moonback.listen(port=0)
    let task = group.spawn(() => app.serve(server))
    let (response, body) = @http.get(
      "http://127.0.0.1:\{server.addr.port()}\{path}",
    )
    task.cancel()
    (response.code, response.headers.get("content-type"), body.text())
  })
}

///|
async test "static middleware serves existing file" {
  let (code, content_type, body) = send_request(
    new(root=fixture_root),
    "/app.js",
  )
  debug_inspect(code, content="200")
  debug_inspect(
    content_type,
    content="Some(\"text/javascript; charset=utf-8\")",
  )
  debug_inspect(
    body.trim(),
    content=(
      #|<StringView: "console.log('static middleware');">
    ),
  )
}

///|
async test "static middleware rewrites trailing slash to index" {
  let (code, _content_type, body) = send_request(
    new(root=fixture_root, rewrite_trailing_slash_index=true),
    "/docs/",
  )
  debug_inspect(code, content="200")
  debug_inspect(
    body.trim(),
    content=(
      #|<StringView: "<h1>docs index</h1>">
    ),
  )
}

///|
async test "static middleware falls through when trailing slash rewrite disabled" {
  let (code, _content_type, body) = send_request(
    new(root=fixture_root, rewrite_trailing_slash_index=false),
    "/docs/",
  )
  debug_inspect(code, content="404")
  debug_inspect(
    body,
    content=(
      #|""
    ),
  )
}

///|
async test "static middleware serves history fallback for route path" {
  let (code, _content_type, body) = send_request(
    new(root=fixture_root, history_fallback=Some("/index.html")),
    "/dashboard",
  )
  debug_inspect(code, content="200")
  debug_inspect(
    body.trim(),
    content=(
      #|<StringView: "<h1>root index</h1>">
    ),
  )
}

///|
async test "static middleware keeps next response when next is not 404" {
  let (code, _content_type, body) = send_request(
    new(root=fixture_root, history_fallback=Some("index.html")),
    "/dashboard",
    extra_routes=Module(ctx => {
      ctx.get("/dashboard", (_req, res) => {
        let writer = res.respond(status=200)
        writer.write("from route")
      })
    }),
  )
  debug_inspect(code, content="200")
  debug_inspect(
    body,
    content=(
      #|"from route"
    ),
  )
}

///|
async test "static middleware uses history fallback when next returns 404" {
  let (code, _content_type, body) = send_request(
    new(root=fixture_root, history_fallback=Some("/index.html")),
    "/dashboard",
    extra_routes=Module(ctx => {
      ctx.get("/dashboard", (_req, res) => {
        let writer = res.respond(status=404)
        writer.write("route 404")
      })
    }),
  )
  debug_inspect(code, content="200")
  debug_inspect(
    body.trim(),
    content=(
      #|<StringView: "<h1>root index</h1>">
    ),
  )
}

///|
async test "static middleware does not use history fallback for asset-like path" {
  let (code, _content_type, body) = send_request(
    new(root=fixture_root, history_fallback=Some("index.html")),
    "/missing.js",
  )
  debug_inspect(code, content="404")
  debug_inspect(
    body,
    content=(
      #|""
    ),
  )
}
