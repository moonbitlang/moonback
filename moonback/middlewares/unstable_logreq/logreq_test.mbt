///|
struct CaptureWriter {
  log : StringBuilder
  controller : @io.BinaryWriterController
}

///|
impl @io.BinaryWriter for CaptureWriter

///|
impl @io.BinaryWriterImpl for CaptureWriter with fn get_controller(self) {
  self.controller
}

///|
impl @io.BinaryWriterImpl for CaptureWriter with fn raw_write_impl(
  self,
  buf,
  offset~,
  len~,
) {
  self.log.write_string(@utf8.decode(buf[offset:offset + len]))
  len
}

///|
async fn send_request(
  meth : @http.RequestMethod,
  path : String,
  status~ : Int32 = 204,
) -> String {
  let captured = {
    log: StringBuilder(),
    controller: @io.BinaryWriterController(),
  }
  let app = @moonback.App(
    Module(ctx => {
      ctx.add_middleware(@unstable_logreq.new(captured))
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
        let _ = @http.get_binary(url)
      }
      Post => {
        let _ = @http.post_binary(url, b"")
      }
      _ => fail("unsupported test method")
    }
    task.cancel()
  })
  captured.log.to_string()
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
