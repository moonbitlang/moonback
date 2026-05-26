///|
struct CaptureWriter {
  log : StringBuilder
}

///|
impl @io.Writer for CaptureWriter with fn write_once(self, buf, offset~, len~) {
  self.log.write_string(@utf8.decode(buf[offset:offset + len]))
  len
}

///|
async fn send_request(
  meth : @http.RequestMethod,
  path : String,
  status? : Int = 204,
) -> String {
  let captured = { log: StringBuilder::new() }
  let app = @moonback.App(
    @moonback.Module(ctx => {
      ctx.add_middleware(new(captured))
      ctx.add_route(meth, path, (_req, res) => res.send_void(status~))
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = @moonback.listen(port=0)
    let task = group.spawn(() => app.serve(server))
    let url = "http://127.0.0.1:\{server.addr.port()}\{path}"
    match meth {
      Get => {
        let _ = @http.get(url)
      }
      Post => {
        let _ = @http.post(url, "")
      }
      _ => fail("unsupported test method")
    }
    task.cancel()
    captured.log.to_string()
  })
}

///|
async test "logreq logs get request line" {
  let log = send_request(Get, "/api/ping")
  assert_true(log.has_prefix("["))
  assert_true(log.contains("] GET /api/ping -> 204 ("))
  assert_true(log.has_suffix("ms)\n"))
}

///|
async test "logreq logs post request line with query" {
  let log = send_request(Post, "/submit", status=201)
  assert_true(log.has_prefix("["))
  assert_true(log.contains("] POST /submit -> 201 ("))
  assert_true(log.has_suffix("ms)\n"))
}
