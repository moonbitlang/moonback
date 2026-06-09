///|
suberror IdleKeepAliveHandledTimeout

///|
suberror IdleKeepAliveCancelTimeout

///|
suberror HandlerFailure

///|
struct NoopWriteFlusher {}

///|
impl @io.Writer for NoopWriteFlusher with fn write_once(
  _self,
  _buf,
  offset~,
  len~,
) {
  let _ = offset
  len
}

///|
impl Flusher for NoopWriteFlusher with fn flush(_self) -> Unit {
  ()
}

///|
impl WriteFlusher for NoopWriteFlusher

///|
async fn run_with_fake_responder(app : App) -> Array[Int] {
  let statuses = []
  let writer = NoopWriteFlusher::{  }
  @async.with_task_group(group => {
    let req : Request = {
      ctx: Context::new(app, Mock),
      meth: Get,
      path: "/",
      search: None,
      headers: Headers::default(),
      params: {},
      body: { group, state: Unbuffered },
    }
    app.handle_request(
      req,
      Responder((status, _headers) => {
        statuses.push(status)
        writer
      }),
    )
  })
  statuses
}

///|
async test "handle request sends 500 when handler fails before response" {
  let app = App(
    Module(ctx => ctx.get("/", (_req, _res) => raise HandlerFailure)),
  )
  defer app.close()
  @test.assert_eq(run_with_fake_responder(app), [500])
}

///|
async test "handle request does not send 500 after response started" {
  let app = App(
    Module(ctx => {
      ctx.get("/", (_req, res) => {
        res.send_void(status=204)
        raise HandlerFailure
      })
    }),
  )
  defer app.close()
  @test.assert_eq(run_with_fake_responder(app), [204])
}

///|
async test "serve cancels idle keep-alive connections" {
  let mut handled = false
  let app = App(
    Module(ctx => {
      ctx.get("/", (_req, res) => {
        handled = true
        res.send_text("ok")
      })
    }),
    config=Config(stop_timeout=0.05),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    defer conn.close()
    conn.write(
      "GET / HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nConnection: keep-alive\r\n\r\n",
    )
    @async.with_timeout(
      500,
      () => {
        while !handled {
          @async.sleep(10)
        }
      },
      error=IdleKeepAliveHandledTimeout,
    )
    serve_task.cancel()
    @async.with_timeout(
      500,
      () => serve_task.wait(),
      error=IdleKeepAliveCancelTimeout,
    ) catch {
      err if @async.is_cancellation_error(err) => ()
      err => raise err
    }
  })
}
