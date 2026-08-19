///|
async fn run_handler(
  middleware : @moonback.Middleware,
  config? : @moonback.Config = @moonback.Config::default(),
  request_headers? : @http.Headers = {},
) -> (String?, String?) {
  let mut seen_request_id = None
  let app = @moonback.App(
    Module(ctx => {
      ctx.add_middleware(middleware)
      ctx.get("/", (req, res) => {
        seen_request_id = get(req)
        res.send_void(status=204)
      })
    }),
    config~,
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = @moonback.listen(port=0)
    let task = group.spawn(() => app.serve(server))
    let port = server.addr.port()
    let (response, _body) = @http.get(
      "http://127.0.0.1:\{port}/",
      headers=request_headers,
    )
    task.cancel()
    (seen_request_id, response.headers.get("x-request-id"))
  })
}

///|
async test "request id middleware generates id and sets response header" {
  let (request_id, header) = run_handler(new(generator=() => "generated-id"))
  debug_inspect(request_id, content="Some(\"generated-id\")")
  debug_inspect(header, content="Some(\"generated-id\")")
}

///|
async test "request id middleware trusts proxy header when enabled" {
  let (request_id, header) = run_handler(
    new(generator=() => "generated-id"),
    config=Config(trust_proxy=true),
    request_headers={ "X-Request-ID": "proxy-id" },
  )
  debug_inspect(request_id, content="Some(\"proxy-id\")")
  debug_inspect(header, content="Some(\"proxy-id\")")
}

///|
async test "request id middleware skips response header when disabled" {
  let (request_id, header) = run_handler(
    new(generator=() => "generated-id", header=None),
  )
  debug_inspect(request_id, content="Some(\"generated-id\")")
  debug_inspect(header, content="None")
}
